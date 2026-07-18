import AppKit
import AVFoundation
import Vision
import CoreGraphics
import CoreMedia
import CoreVideo
import ImageIO
import ApplicationServices

/// Camera-based hand-gesture control, so you can drive the Mac without touching it while Jarvis is
/// running. It watches the front camera with Vision's hand-pose detector and maps gestures to input:
///
///   • Point with your index finger        → move the cursor
///   • Pinch (thumb + index touch)          → click
///   • Two fingers (index + middle) up/down → scroll
///   • Open palm swipe left / right         → switch to the previous / next Space (desktop)
///   • Pinch and spread apart / together    → zoom in / out (⌘+ / ⌘−)
///   • Fist                                 → do nothing (rest position)
///
/// Everything is best-effort gesture recognition; it's opt-in (config.allowMotionControl, off by
/// default) and needs Camera permission. Nothing here reads or stores video — frames are analysed in
/// memory for hand landmarks only.
final class MotionControl: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "jarvis.motioncontrol.camera")
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()

    private(set) var isRunning = false

    // Smoothed cursor + gesture bookkeeping.
    private var smoothed: CGPoint?
    private var lastPinchDistance: CGFloat?
    private var lastScrollY: CGFloat?
    private var lastSwipeX: CGFloat?
    private var lastActionAt: [String: Date] = [:]
    private var lastLogAt = Date.distantPast

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }

        // Moving the cursor / keys needs Accessibility trust. Because ad-hoc signing re-signs the app
        // on every rebuild, a previously-granted entry can look enabled in System Settings but no
        // longer apply to the new binary — the classic reason gestures do nothing though the camera
        // works. Surface it loudly.
        if !AXIsProcessTrusted() {
            Logger.shared.log("Motion control: ACCESSIBILITY IS NOT TRUSTED for this build — cursor/keyboard gestures will be ignored even though the camera works. Fix: System Settings > Privacy & Security > Accessibility, REMOVE the old JarvisAssistant entry with the – button, then add ~/Applications/JarvisAssistant.app again (a rebuild changes the app's signature, so the old grant no longer applies).")
        } else {
            Logger.shared.log("Motion control: Accessibility is trusted. Good.")
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        Logger.shared.log("Motion control: requested. Current camera authorization = \(status.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized).")
        switch status {
        case .denied, .restricted:
            Logger.shared.log("Motion control: camera access is denied. Turn it on in System Settings > Privacy & Security > Camera for JarvisAssistant, then re-enable Motion Control. If JarvisAssistant isn't listed, run: tccutil reset Camera com.jarvis.assistant")
            return
        default:
            break
        }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                Logger.shared.log("Motion control: camera permission not granted.")
                return
            }
            self.queue.async { self.configureAndRun() }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configureAndRun() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        // Prefer the front camera.
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            Logger.shared.log("Motion control: no usable camera found.")
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
        session.startRunning()
        isRunning = true
        Logger.shared.log("Motion control started (front camera, hand-pose).")
    }

    // MARK: - Frame processing

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRunning, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }
        guard let hand = request.results?.first else {
            smoothed = nil; lastPinchDistance = nil; lastScrollY = nil; lastSwipeX = nil
            return
        }
        process(hand)
    }

    private func point(_ hand: VNHumanHandPoseObservation, _ joint: VNHumanHandPoseObservation.JointName) -> CGPoint? {
        guard let p = try? hand.recognizedPoint(joint), p.confidence > 0.3 else { return nil }
        return CGPoint(x: p.location.x, y: p.location.y)  // normalized, origin bottom-left
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// True if a finger is extended (its tip is farther from the wrist than its middle joint).
    private func extended(_ hand: VNHumanHandPoseObservation, tip: VNHumanHandPoseObservation.JointName,
                          pip: VNHumanHandPoseObservation.JointName, wrist: CGPoint) -> Bool {
        guard let t = point(hand, tip), let p = point(hand, pip) else { return false }
        return dist(t, wrist) > dist(p, wrist) * 1.05
    }

    private func process(_ hand: VNHumanHandPoseObservation) {
        guard let wrist = point(hand, .wrist) else { return }
        let indexUp  = extended(hand, tip: .indexTip,  pip: .indexPIP,  wrist: wrist)
        let middleUp = extended(hand, tip: .middleTip, pip: .middlePIP, wrist: wrist)
        let ringUp   = extended(hand, tip: .ringTip,   pip: .ringPIP,   wrist: wrist)
        let littleUp = extended(hand, tip: .littleTip, pip: .littlePIP, wrist: wrist)
        let extendedCount = [indexUp, middleUp, ringUp, littleUp].filter { $0 }.count

        let indexTip = point(hand, .indexTip)
        let thumbTip = point(hand, .thumbTip)
        let pinchD: CGFloat? = (indexTip != nil && thumbTip != nil) ? dist(indexTip!, thumbTip!) : nil

        // Heartbeat so the log shows detection is happening (throttled to ~1.5s).
        if Date().timeIntervalSince(lastLogAt) > 1.5 {
            lastLogAt = Date()
            let idxStr = indexTip.map { "(\(String(format: "%.2f", $0.x)),\(String(format: "%.2f", $0.y)))" } ?? "nil"
            Logger.shared.log("Motion control: hand detected — extended fingers=\(extendedCount) index=\(indexUp) middle=\(middleUp) indexTip=\(idxStr) axTrusted=\(AXIsProcessTrusted()).")
        }

        // ----- Open palm: swipe between Spaces -----
        if extendedCount >= 4 {
            if let last = lastSwipeX {
                let dx = wrist.x - last
                if abs(dx) > 0.16 {
                    // Camera is mirrored: moving your hand right pushes your wrist.x left.
                    if dx < 0 { fireSpace(right: true) } else { fireSpace(right: false) }
                    lastSwipeX = wrist.x
                }
            } else {
                lastSwipeX = wrist.x
            }
            resetPointerState(keepSwipe: true)
            return
        }
        lastSwipeX = nil

        // ----- Pinch: click, or spread/close to zoom -----
        if let d = pinchD, indexUp || middleUp {
            if let prev = lastPinchDistance {
                let delta = d - prev
                if abs(delta) > 0.05 {
                    zoom(inward: delta < 0)   // fingers closing = zoom out; spreading = zoom in
                    lastPinchDistance = d
                }
            }
            if d < 0.05 {                     // a firm pinch = click
                click()
            }
            lastPinchDistance = d
        } else {
            lastPinchDistance = nil
        }

        // ----- Two fingers: scroll -----
        if indexUp && middleUp && !ringUp && !littleUp, let tip = indexTip {
            if let last = lastScrollY {
                let dy = tip.y - last
                if abs(dy) > 0.01 { scroll(by: dy * 900) }
            }
            lastScrollY = tip.y
            smoothed = nil
            return
        }
        lastScrollY = nil

        // ----- One finger: move the cursor -----
        if indexUp && !middleUp, let tip = indexTip {
            moveCursor(toNormalized: tip)
        } else {
            smoothed = nil
        }
    }

    private func resetPointerState(keepSwipe: Bool) {
        smoothed = nil; lastScrollY = nil; lastPinchDistance = nil
        if !keepSwipe { lastSwipeX = nil }
    }

    // MARK: - Actions (dispatched to the main thread)

    private func throttled(_ key: String, _ interval: TimeInterval) -> Bool {
        let now = Date()
        if let last = lastActionAt[key], now.timeIntervalSince(last) < interval { return false }
        lastActionAt[key] = now
        return true
    }

    private func screenSize() -> CGSize { NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900) }

    private func moveCursor(toNormalized n: CGPoint) {
        let size = screenSize()
        // Mirror x (front camera), flip y (Vision y is up, screen y is down).
        let target = CGPoint(x: (1 - n.x) * size.width, y: (1 - n.y) * size.height)
        let s = smoothed ?? target
        let eased = CGPoint(x: s.x + (target.x - s.x) * 0.35, y: s.y + (target.y - s.y) * 0.35)
        smoothed = eased
        DispatchQueue.main.async {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: eased, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }

    private func click() {
        guard throttled("click", 0.6) else { return }
        let pos = smoothed ?? CGEvent(source: nil)?.location ?? .zero
        DispatchQueue.main.async {
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private func scroll(by amount: CGFloat) {
        DispatchQueue.main.async {
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(amount), wheel2: 0, wheel3: 0)?
                .post(tap: .cghidEventTap)
        }
    }

    private func fireSpace(right: Bool) {
        guard throttled("space", 0.8) else { return }
        // Control + Left/Right arrow = "Move to the space on the left/right" (default macOS shortcut).
        postKey(keyCode: right ? 124 : 123, control: true)
    }

    private func zoom(inward: Bool) {
        guard throttled("zoom", 0.25) else { return }
        // Command + '=' zooms in, Command + '-' zooms out (works in most document/browser apps).
        postKey(keyCode: inward ? 24 : 27, command: true)
    }

    private func postKey(keyCode: CGKeyCode, command: Bool = false, control: Bool = false) {
        DispatchQueue.main.async {
            var flags: CGEventFlags = []
            if command { flags.insert(.maskCommand) }
            if control { flags.insert(.maskControl) }
            let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            down?.flags = flags
            up?.flags = flags
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
