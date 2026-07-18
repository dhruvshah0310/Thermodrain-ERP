import AppKit

/// Sumo — Thermodrain's mascot — drawn procedurally so he can act out what Jarvis is doing:
///   • listening  → leans in and cups a hand to his ear
///   • thinking    → sinks into a cross-legged meditation pose, eyes closed
///   • speaking    → mouth moves in time with Jarvis's voice while his hands gesture
/// He also springs in with a little bounce when he appears. All state is a set of eased parameters
/// advanced by a ~30 fps timer; `draw(_:)` renders the current pose from them, so pose changes are
/// just smooth interpolations rather than a rigged layer tree.
final class SumoView: NSView {
    enum Pose { case listening, thinking, speaking }

    // Targets set by the current pose; `cur*` values ease toward them each frame.
    private var tSeated: CGFloat = 0, curSeated: CGFloat = 0
    private var tEar: CGFloat = 0, curEar: CGFloat = 0
    private var tGesture: CGFloat = 0, curGesture: CGFloat = 0
    private var tEyesClosed: CGFloat = 0, curEyesClosed: CGFloat = 0
    private var tTilt: CGFloat = 0, curTilt: CGFloat = 0
    private var tMouth: CGFloat = 0, curMouth: CGFloat = 0   // 0…1 mouth openness (voice level)

    private var bobPhase: CGFloat = 0
    private var gesturePhase: CGFloat = 0

    // Entrance spring (bouncy pop-in).
    private var appearPos: CGFloat = 0, appearVel: CGFloat = 0

    private var timer: Timer?

    // Palette — Thermodrain steel-blue mawashi against warm skin.
    private let skin      = NSColor(calibratedRed: 0.95, green: 0.80, blue: 0.66, alpha: 1)
    private let skinShade = NSColor(calibratedRed: 0.86, green: 0.68, blue: 0.53, alpha: 1)
    private let belt      = NSColor(calibratedRed: 0.11, green: 0.36, blue: 0.62, alpha: 1)
    private let beltDark  = NSColor(calibratedRed: 0.07, green: 0.26, blue: 0.47, alpha: 1)
    private let hair      = NSColor(calibratedRed: 0.16, green: 0.14, blue: 0.15, alpha: 1)
    private let mouthCol  = NSColor(calibratedRed: 0.45, green: 0.16, blue: 0.16, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        startLoop()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        startLoop()
    }
    deinit { timer?.invalidate() }

    override var isFlipped: Bool { false }  // y-up: feet at the bottom

    // MARK: - Public API

    func setPose(_ pose: Pose) {
        switch pose {
        case .listening: tSeated = 0; tEar = 1; tGesture = 0; tEyesClosed = 0; tTilt = 0.14
        case .thinking:  tSeated = 1; tEar = 0; tGesture = 0; tEyesClosed = 1; tTilt = 0
        case .speaking:  tSeated = 0; tEar = 0; tGesture = 1; tEyesClosed = 0; tTilt = 0
        }
    }

    /// Voice loudness (0…1) → mouth openness while speaking.
    func setLevel(_ level: Float) {
        tMouth = CGFloat(min(max(level, 0), 1))
    }

    /// Kick off the bouncy entrance (call each time he's shown).
    func playAppear() {
        appearPos = 0
        appearVel = 0
    }

    // MARK: - Animation loop

    private func startLoop() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        let dt: CGFloat = 1.0 / 30.0
        bobPhase += dt * 2.2
        gesturePhase += dt * 7.0

        // Ease pose parameters.
        curSeated     += (tSeated - curSeated) * 0.16
        curEar        += (tEar - curEar) * 0.18
        curGesture    += (tGesture - curGesture) * 0.15
        curEyesClosed += (tEyesClosed - curEyesClosed) * 0.25
        curTilt       += (tTilt - curTilt) * 0.18
        curMouth      += (tMouth - curMouth) * 0.4
        tMouth        *= 0.90  // sag when no fresh audio arrives

        // Entrance spring toward 1 with overshoot.
        let stiffness: CGFloat = 180, damping: CGFloat = 14
        let force = (1 - appearPos) * stiffness - appearVel * damping
        appearVel += force * dt
        appearPos += appearVel * dt

        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        let u = min(w, h)
        let cx = w / 2
        let footY = h * 0.16
        let alpha = max(0, min(1, appearPos * 1.3))
        let scale = 0.62 + 0.38 * appearPos           // springs slightly past 1
        let bob = sin(bobPhase) * u * 0.012 * (1 - curSeated)

        // Entrance transform: scale about the feet.
        NSGraphicsContext.saveGraphicsState()
        let xf = NSAffineTransform()
        xf.translateX(by: cx, yBy: footY)
        xf.scale(by: scale)
        xf.translateX(by: -cx, yBy: -footY)
        xf.concat()

        let sink = curSeated * u * 0.16               // whole body lowers when meditating
        let spread = 1 + curSeated * 0.28             // and widens at the base

        // Ground shadow.
        let shW = u * 0.5 * spread, shH = u * 0.07
        fill(oval(cx - shW/2, footY - shH*0.3, shW, shH), NSColor.black.withAlphaComponent(0.16 * alpha))

        // Legs / seated base.
        drawLegs(cx: cx, footY: footY, u: u, seated: curSeated, alpha: alpha)

        // Body (belly).
        let bellyW = u * 0.60 * spread
        let bellyH = u * 0.46
        let bellyBottom = footY + u * 0.09 - sink * 0.2
        let bellyCX = cx
        let bellyCY = bellyBottom + bellyH / 2
        fill(oval(bellyCX - bellyW/2, bellyBottom, bellyW, bellyH), skin.withAlphaComponent(alpha))
        // Soft belly shading.
        fill(oval(bellyCX - bellyW*0.30, bellyBottom + bellyH*0.10, bellyW*0.34, bellyH*0.5),
             skinShade.withAlphaComponent(0.35 * alpha))

        // Mawashi (belt).
        let beltY = bellyBottom + bellyH * 0.06
        let beltH = bellyH * 0.26
        fill(roundedRect(bellyCX - bellyW*0.52, beltY, bellyW*1.04, beltH, beltH*0.35),
             belt.withAlphaComponent(alpha))
        fill(roundedRect(bellyCX - bellyW*0.10, beltY - beltH*0.35, bellyW*0.20, beltH*1.35, bellyW*0.05),
             beltDark.withAlphaComponent(alpha))  // front flap

        // Arms (behind head, gesture while speaking; rest on knees when seated).
        let shoulderY = bellyCY + bellyH * 0.16
        let g = curGesture
        let swing = sin(gesturePhase) * 0.5 * g
        let leftArmAngle:  CGFloat = 0.5 + swing + curSeated * 0.35
        let rightArmAngle: CGFloat = -0.5 - swing - curSeated * 0.35 - curEar * 0.9
        drawArm(shoulderX: bellyCX - bellyW*0.44, shoulderY: shoulderY, angle: leftArmAngle, u: u, alpha: alpha)
        drawArm(shoulderX: bellyCX + bellyW*0.44, shoulderY: shoulderY, angle: rightArmAngle, u: u, alpha: alpha)

        // Head (+ face), leaning forward when listening.
        let headR = u * 0.165
        let lean = curEar * u * 0.05
        let headCX = cx + lean
        let headCY = bellyCY + bellyH/2 + headR*0.62 - sink*0.4 + bob
        drawHead(cx: headCX, cy: headCY, r: headR, alpha: alpha)

        // Cupped hand at the ear when listening.
        if curEar > 0.02 {
            let hx = headCX + headR*1.02, hy = headCY + headR*0.05
            fill(oval(hx - headR*0.34, hy - headR*0.34, headR*0.68, headR*0.72),
                 skin.withAlphaComponent(alpha * curEar))
            fill(oval(hx - headR*0.34, hy - headR*0.34, headR*0.68, headR*0.72).stroked(headR*0.10),
                 skinShade.withAlphaComponent(0.5 * alpha * curEar))
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHead(cx: CGFloat, cy: CGFloat, r: CGFloat, alpha: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let xf = NSAffineTransform()
        xf.translateX(by: cx, yBy: cy)
        xf.rotate(byRadians: curTilt)
        xf.concat()

        // Face.
        fill(oval(-r, -r, r*2, r*2), skin.withAlphaComponent(alpha))

        // Topknot (chonmage): a dark cap + a little knot on top.
        fill(oval(-r*0.9, r*0.15, r*1.8, r*0.95), hair.withAlphaComponent(alpha))
        fill(oval(-r*0.24, r*0.78, r*0.48, r*0.5), hair.withAlphaComponent(alpha))
        // Ears.
        fill(oval(-r*1.06, -r*0.18, r*0.36, r*0.5), skin.withAlphaComponent(alpha))
        fill(oval(r*0.70, -r*0.18, r*0.36, r*0.5), skin.withAlphaComponent(alpha))

        // Eyes — open (dots) or closed (arcs) by curEyesClosed.
        let ex = r*0.42, ey = r*0.16, eo = 1 - curEyesClosed
        if eo > 0.05 {
            fill(oval(-ex - r*0.12, ey - r*0.12, r*0.24, r*0.24), hair.withAlphaComponent(alpha*eo))
            fill(oval(ex - r*0.12, ey - r*0.12, r*0.24, r*0.24), hair.withAlphaComponent(alpha*eo))
        }
        if curEyesClosed > 0.05 {
            strokeArc(cxp: -ex, cyp: ey, r: r*0.2, alpha: alpha*curEyesClosed)
            strokeArc(cxp: ex, cyp: ey, r: r*0.2, alpha: alpha*curEyesClosed)
        }

        // Mouth — opens with the voice while speaking; a calm line otherwise.
        let open = curMouth * (1 - curEyesClosed)
        let my = -r*0.42
        if open > 0.04 {
            let mw = r*0.5, mh = r*0.15 + r*0.7*open
            fill(oval(-mw/2, my - mh/2, mw, mh), mouthCol.withAlphaComponent(alpha))
        } else {
            let line = NSBezierPath()
            line.lineWidth = r*0.09
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: -r*0.26, y: my))
            line.curve(to: NSPoint(x: r*0.26, y: my),
                       controlPoint1: NSPoint(x: -r*0.05, y: my - r*0.14),
                       controlPoint2: NSPoint(x: r*0.05, y: my - r*0.14))
            mouthCol.withAlphaComponent(alpha).setStroke()
            line.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawArm(shoulderX: CGFloat, shoulderY: CGFloat, angle: CGFloat, u: CGFloat, alpha: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let xf = NSAffineTransform()
        xf.translateX(by: shoulderX, yBy: shoulderY)
        xf.rotate(byRadians: angle)
        xf.concat()
        let armW = u*0.16, armL = u*0.30
        fill(roundedRect(-armW/2, -armL, armW, armL, armW/2), skin.withAlphaComponent(alpha))
        fill(oval(-armW*0.55, -armL - armW*0.4, armW*1.1, armW*1.1), skin.withAlphaComponent(alpha)) // hand
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawLegs(cx: CGFloat, footY: CGFloat, u: CGFloat, seated: CGFloat, alpha: CGFloat) {
        let stand = 1 - seated
        if stand > 0.03 {
            let legW = u*0.17, legH = u*0.14
            fill(roundedRect(cx - u*0.20, footY - legH*0.1, legW, legH, legW*0.4), skin.withAlphaComponent(alpha*stand))
            fill(roundedRect(cx + u*0.03, footY - legH*0.1, legW, legH, legW*0.4), skin.withAlphaComponent(alpha*stand))
        }
        if seated > 0.03 {
            // Crossed-legs base: a wide low rounded mound.
            let baseW = u*0.66, baseH = u*0.20
            fill(roundedRect(cx - baseW/2, footY - baseH*0.2, baseW, baseH, baseH*0.5), skin.withAlphaComponent(alpha*seated))
            fill(roundedRect(cx - baseW*0.30, footY + baseH*0.15, baseW*0.60, baseH*0.5, baseH*0.25),
                 skinShade.withAlphaComponent(0.4*alpha*seated))  // fold shading
        }
    }

    // MARK: - Shape helpers

    private func fill(_ path: NSBezierPath, _ color: NSColor) { color.setFill(); path.fill() }
    private func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: w, height: h))
    }
    private func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }
    private func strokeArc(cxp: CGFloat, cyp: CGFloat, r: CGFloat, alpha: CGFloat) {
        let p = NSBezierPath()
        p.lineWidth = r*0.28
        p.lineCapStyle = .round
        p.appendArc(withCenter: NSPoint(x: cxp, y: cyp), radius: r, startAngle: 200, endAngle: 340)
        hair.withAlphaComponent(alpha).setStroke()
        p.stroke()
    }
}

private extension NSBezierPath {
    /// A thin ring version of this path's bounds (used for a simple hand outline).
    func stroked(_ width: CGFloat) -> NSBezierPath {
        let r = bounds
        let outer = NSBezierPath(ovalIn: r)
        let inner = NSBezierPath(ovalIn: r.insetBy(dx: width, dy: width))
        outer.append(inner.reversed)
        return outer
    }
}

/// A Siri-style floating window — now with a transparent background so Sumo simply appears on the
/// desktop (no boxy panel). Floats above everything, never takes focus, passes clicks through.
final class HUDWindowController {
    private let panel: NSPanel
    private let sumo = SumoView(frame: NSRect(x: 0, y: 0, width: 150, height: 150))
    private let statusLabel = NSTextField(labelWithString: "")
    private let messageLabel: NSTextField
    private var pendingHide: DispatchWorkItem?

    init() {
        let size = NSSize(width: 360, height: 250)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.alphaValue = 0

        // Plain transparent container — no blurred box.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]

        // Legible over any wallpaper: white text with a soft dark shadow.
        let textShadow = NSShadow()
        textShadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        textShadow.shadowBlurRadius = 5
        textShadow.shadowOffset = NSSize(width: 0, height: -1)

        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.wantsLayer = true
        statusLabel.shadow = textShadow

        messageLabel = NSTextField(wrappingLabelWithString: "")
        messageLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        messageLabel.textColor = .white
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.preferredMaxLayoutWidth = size.width - 40
        messageLabel.wantsLayer = true
        messageLabel.shadow = textShadow

        sumo.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [sumo, statusLabel, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            sumo.widthAnchor.constraint(equalToConstant: 150),
            sumo.heightAnchor.constraint(equalToConstant: 150),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16)
        ])

        panel.contentView = container
    }

    // MARK: - State transitions (call on the main thread)

    func showListening() {
        present(status: "Listening…", message: "", pose: .listening)
    }

    func showThinking(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        present(status: "Working on it…", message: trimmed.isEmpty ? "" : "“\(trimmed)”", pose: .thinking)
    }

    func showSpeaking(_ reply: String) {
        present(status: "Sumo", message: reply.trimmingCharacters(in: .whitespacesAndNewlines), pose: .speaking)
    }

    /// Live loudness (0…1) → Sumo's mouth.
    func setLevel(_ level: Float) {
        sumo.setLevel(level)
    }

    private func present(status: String, message: String, pose: SumoView.Pose) {
        pendingHide?.cancel()
        pendingHide = nil
        statusLabel.stringValue = status
        messageLabel.stringValue = message
        messageLabel.isHidden = message.isEmpty
        sumo.setPose(pose)
        let wasHidden = panel.alphaValue < 0.5
        if wasHidden { sumo.playAppear() }   // bounce in only when first appearing
        positionPanel()
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func scheduleHide(after delay: TimeInterval = 1.8) {
        pendingHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let s = panel.frame.size
        let x = visible.midX - s.width / 2
        let y = visible.minY + 120
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// The menu-bar glyph: a small monochrome Sumo silhouette (a template image, so macOS tints it).
enum JarvisIcon {
    static func sumo() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let w = rect.width, h = rect.height, cx = rect.midX
            // Body.
            NSBezierPath(ovalIn: NSRect(x: cx - w*0.34, y: h*0.10, width: w*0.68, height: h*0.55)).fill()
            // Head.
            NSBezierPath(ovalIn: NSRect(x: cx - w*0.20, y: h*0.52, width: w*0.40, height: h*0.40)).fill()
            // Topknot.
            NSBezierPath(ovalIn: NSRect(x: cx - w*0.07, y: h*0.84, width: w*0.14, height: h*0.13)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
