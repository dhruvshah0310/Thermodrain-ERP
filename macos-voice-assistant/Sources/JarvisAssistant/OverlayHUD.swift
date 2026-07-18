import AppKit

/// Sumo — Thermodrain's mascot — drawn as sleek line-art (outline only, no fills): navy contours with
/// gold/orange accent strokes, and an angry, furrowed expression. He acts out what Jarvis is doing:
///   • listening → head leans in, one hand cupped to the ear
///   • thinking   → drops into a low sumo squat, eyes narrowed in focus
///   • speaking   → mouth moves in time with Jarvis's voice while his hands gesture
/// He springs in with a bounce. All state is a set of eased parameters advanced by a ~30 fps timer;
/// `draw(_:)` re-renders the current pose from them, so pose changes are smooth interpolations.
final class SumoView: NSView {
    enum Pose { case listening, thinking, speaking }

    private var tSquat: CGFloat = 0, cSquat: CGFloat = 0
    private var tEar: CGFloat = 0, cEar: CGFloat = 0
    private var tGesture: CGFloat = 0, cGesture: CGFloat = 0
    private var tNarrow: CGFloat = 0, cNarrow: CGFloat = 0   // eyes narrowed (focus)
    private var tTilt: CGFloat = 0, cTilt: CGFloat = 0
    private var tMouth: CGFloat = 0, cMouth: CGFloat = 0

    private var bobPhase: CGFloat = 0
    private var gesturePhase: CGFloat = 0
    private var appearPos: CGFloat = 0, appearVel: CGFloat = 0
    private var timer: Timer?

    // Line-art palette: deep navy contour, warm gold + orange accents (as in the reference).
    private let navy   = NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.42, alpha: 1)
    private let gold   = NSColor(calibratedRed: 0.86, green: 0.64, blue: 0.20, alpha: 1)
    private let orange = NSColor(calibratedRed: 0.87, green: 0.42, blue: 0.18, alpha: 1)

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

    override var isFlipped: Bool { false }

    // MARK: - API

    func setPose(_ pose: Pose) {
        switch pose {
        case .listening: tSquat = 0; tEar = 1; tGesture = 0; tNarrow = 0.35; tTilt = 0.13
        case .thinking:  tSquat = 1; tEar = 0; tGesture = 0; tNarrow = 0.75; tTilt = 0
        case .speaking:  tSquat = 0; tEar = 0; tGesture = 1; tNarrow = 0.2;  tTilt = 0
        }
    }
    func setLevel(_ level: Float) { tMouth = CGFloat(min(max(level, 0), 1)) }
    func playAppear() { appearPos = 0; appearVel = 0 }

    // MARK: - Loop

    private func startLoop() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        let dt: CGFloat = 1.0 / 30.0
        bobPhase += dt * 2.0
        gesturePhase += dt * 7.0
        cSquat   += (tSquat - cSquat) * 0.16
        cEar     += (tEar - cEar) * 0.18
        cGesture += (tGesture - cGesture) * 0.15
        cNarrow  += (tNarrow - cNarrow) * 0.2
        cTilt    += (tTilt - cTilt) * 0.18
        cMouth   += (tMouth - cMouth) * 0.45
        tMouth   *= 0.86
        let force = (1 - appearPos) * 180 - appearVel * 14
        appearVel += force * dt
        appearPos += appearVel * dt
        needsDisplay = true
    }

    // MARK: - Drawing (strokes only)

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        let u = min(w, h)
        let cx = w / 2
        let footY = h * 0.14
        let alpha = max(0, min(1, appearPos * 1.3))
        let scale = 0.64 + 0.36 * appearPos
        let bob = sin(bobPhase) * u * 0.010 * (1 - cSquat)
        let lw = u * 0.016
        let aw = u * 0.010

        NSGraphicsContext.saveGraphicsState()
        let xf = NSAffineTransform()
        xf.translateX(by: cx, yBy: footY)
        xf.scale(by: scale)
        xf.translateX(by: -cx, yBy: -footY)
        xf.concat()

        let sink = cSquat * u * 0.14

        // Ground platform ring.
        stroke(oval(cx - u*0.34, footY - u*0.05, u*0.68, u*0.11), navy, lw*0.8, alpha)

        // Hips / body anchor.
        let hipY = footY + u*0.16 - sink*0.2
        let torsoBottom = hipY + u*0.02
        let torsoW = u*0.52 * (1 + cSquat*0.12)
        let torsoH = u*0.40
        let torsoCX = cx
        let torsoCY = torsoBottom + torsoH/2 - sink*0.4

        // Legs (squat when thinking, stand otherwise).
        drawLegs(cx: cx, hipY: hipY, footY: footY, u: u, squat: cSquat, lw: lw, alpha: alpha)

        // Torso outline.
        stroke(oval(torsoCX - torsoW/2, torsoBottom - sink*0.4, torsoW, torsoH), navy, lw, alpha)
        // Accent contours (pecs + belly), the neon-linework look.
        let pecY = torsoCY + torsoH*0.12
        stroke(arcPath(cx: torsoCX - torsoW*0.20, cy: pecY, r: torsoW*0.16, a0: 200, a1: 340), gold, aw, alpha)
        stroke(arcPath(cx: torsoCX + torsoW*0.20, cy: pecY, r: torsoW*0.16, a0: 200, a1: 340), gold, aw, alpha)
        stroke(arcPath(cx: torsoCX, cy: torsoCY - torsoH*0.06, r: torsoW*0.22, a0: 205, a1: 335), orange, aw, alpha)

        // Mawashi belt.
        let beltY = torsoBottom - sink*0.4 + torsoH*0.04
        let beltH = torsoH*0.20
        stroke(roundedRect(torsoCX - torsoW*0.54, beltY, torsoW*1.08, beltH, beltH*0.4), navy, lw, alpha)
        // Front flap with a gold zig-zag accent.
        stroke(roundedRect(torsoCX - torsoW*0.10, beltY - beltH*0.55, torsoW*0.20, beltH*1.4, torsoW*0.04), navy, lw*0.8, alpha)
        stroke(zigzag(cx: torsoCX, top: beltY - beltH*0.4, w: torsoW*0.12, h: beltH*1.1, steps: 3), gold, aw, alpha)

        // Arms.
        let shoulderY = torsoCY + torsoH*0.30
        let swing = sin(gesturePhase) * 0.5 * cGesture
        drawArm(sx: torsoCX - torsoW*0.46, sy: shoulderY, side: -1, u: u, squat: cSquat, ear: 0, gesture: swing, lw: lw, alpha: alpha, hipY: hipY, cx: cx)
        drawArm(sx: torsoCX + torsoW*0.46, sy: shoulderY, side: 1, u: u, squat: cSquat, ear: cEar, gesture: -swing, lw: lw, alpha: alpha, hipY: hipY, cx: cx)

        // Head.
        let headR = u*0.155
        let lean = cEar * u*0.05
        let headCX = cx + lean
        let headCY = torsoCY + torsoH/2 + headR*0.5 - sink*0.4 + bob
        drawHead(cx: headCX, cy: headCY, r: headR, lw: lw, aw: aw, alpha: alpha)

        // Cupped hand at the ear when listening.
        if cEar > 0.02 {
            let hx = headCX + headR*1.05, hy = headCY + headR*0.02
            stroke(oval(hx - headR*0.30, hy - headR*0.34, headR*0.6, headR*0.72), navy, lw*0.9, alpha*cEar)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHead(cx: CGFloat, cy: CGFloat, r: CGFloat, lw: CGFloat, aw: CGFloat, alpha: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let xf = NSAffineTransform()
        xf.translateX(by: cx, yBy: cy); xf.rotate(byRadians: cTilt); xf.concat()

        // Ears, face, topknot — all outlines.
        stroke(oval(-r*1.04, -r*0.20, r*0.34, r*0.5), navy, lw*0.8, alpha)
        stroke(oval(r*0.70, -r*0.20, r*0.34, r*0.5), navy, lw*0.8, alpha)
        stroke(oval(-r, -r, r*2, r*2), navy, lw, alpha)
        stroke(oval(-r*0.66, r*0.62, r*1.32, r*0.7), navy, lw*0.8, alpha)   // hairline cap
        stroke(oval(-r*0.22, r*1.02, r*0.44, r*0.42), navy, lw*0.8, alpha)  // topknot
        stroke(linePath(from: NSPoint(x: -r*0.22, y: r*1.16), to: NSPoint(x: r*0.22, y: r*1.16)), navy, lw*0.7, alpha)

        // Angry eyebrows — thick strokes slanting down toward the nose.
        let browY = r*0.30
        stroke(linePath(from: NSPoint(x: -r*0.66, y: browY + r*0.10), to: NSPoint(x: -r*0.16, y: browY - r*0.10)), navy, lw*1.1, alpha)
        stroke(linePath(from: NSPoint(x: r*0.66, y: browY + r*0.10), to: NSPoint(x: r*0.16, y: browY - r*0.10)), navy, lw*1.1, alpha)

        // Angry eyes — narrowed slits under the brows (an orange glint).
        let eyeY = r*0.06
        let open = (1 - cNarrow)
        let eyeH = r*0.16 * (0.35 + 0.65*open)
        for sgn in [-CGFloat(1), 1] {
            let ex = sgn * r*0.40
            stroke(linePath(from: NSPoint(x: ex - r*0.20, y: eyeY + eyeH), to: NSPoint(x: ex + r*0.20, y: eyeY + eyeH*0.2)), navy, lw*0.9, alpha)
            stroke(linePath(from: NSPoint(x: ex - r*0.20, y: eyeY - eyeH*0.4), to: NSPoint(x: ex + r*0.20, y: eyeY - eyeH*0.4)), navy, lw*0.7, alpha)
            stroke(linePath(from: NSPoint(x: ex - r*0.10, y: eyeY), to: NSPoint(x: ex + r*0.12, y: eyeY)), orange, aw, alpha)
        }

        // Frown / mouth — opens with the voice while speaking; a hard frown otherwise.
        let my = -r*0.44
        let openM = cMouth
        if openM > 0.05 {
            stroke(oval(-r*0.26, my - (r*0.10 + r*0.5*openM)/2, r*0.52, r*0.10 + r*0.5*openM), navy, lw*0.9, alpha)
        } else {
            stroke(curvePath(from: NSPoint(x: -r*0.28, y: my - r*0.06),
                             to: NSPoint(x: r*0.28, y: my - r*0.06),
                             c1: NSPoint(x: -r*0.08, y: my + r*0.10),
                             c2: NSPoint(x: r*0.08, y: my + r*0.10)), navy, lw*0.9, alpha)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawArm(sx: CGFloat, sy: CGFloat, side: CGFloat, u: CGFloat, squat: CGFloat,
                         ear: CGFloat, gesture: CGFloat, lw: CGFloat, alpha: CGFloat, hipY: CGFloat, cx: CGFloat) {
        // Hand target: at the ear (listening), on the knee (squat), or gesturing/at side.
        let elbow = NSPoint(x: sx + side*u*0.10, y: sy - u*0.14 - gesture*u*0.10)
        var hand: NSPoint
        if ear > 0.5 {
            hand = NSPoint(x: cx + side*u*0.14, y: sy + u*0.10)         // up toward the ear
        } else if squat > 0.5 {
            hand = NSPoint(x: cx + side*u*0.22, y: hipY - u*0.02)       // resting on the knee
        } else {
            hand = NSPoint(x: sx + side*u*0.06 + gesture*u*0.14, y: sy - u*0.30 + gesture*u*0.06)
        }
        let arm = NSBezierPath()
        arm.move(to: NSPoint(x: sx, y: sy))
        arm.line(to: elbow)
        arm.line(to: hand)
        stroke(arm, navy, lw, alpha)
        stroke(oval(hand.x - u*0.05, hand.y - u*0.05, u*0.10, u*0.10), navy, lw*0.8, alpha)  // fist/hand
    }

    private func drawLegs(cx: CGFloat, hipY: CGFloat, footY: CGFloat, u: CGFloat, squat: CGFloat, lw: CGFloat, alpha: CGFloat) {
        for sgn in [-CGFloat(1), 1] {
            let hip = NSPoint(x: cx + sgn*u*0.12, y: hipY)
            let knee = NSPoint(x: cx + sgn*(u*0.14 + squat*u*0.16), y: hipY - u*0.10 + squat*u*0.05)
            let foot = NSPoint(x: cx + sgn*(u*0.10 + squat*u*0.04), y: footY)
            let leg = NSBezierPath()
            leg.move(to: hip); leg.line(to: knee); leg.line(to: foot)
            stroke(leg, navy, lw, alpha)
            stroke(oval(foot.x - u*0.07, footY - u*0.02, u*0.14, u*0.05), navy, lw*0.8, alpha)  // foot
        }
    }

    // MARK: - Stroke helpers

    private func stroke(_ path: NSBezierPath, _ color: NSColor, _ width: CGFloat, _ alpha: CGFloat) {
        color.withAlphaComponent(alpha).setStroke()
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }
    private func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: w, height: h))
    }
    private func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }
    private func linePath(from a: NSPoint, to b: NSPoint) -> NSBezierPath {
        let p = NSBezierPath(); p.move(to: a); p.line(to: b); return p
    }
    private func curvePath(from a: NSPoint, to b: NSPoint, c1: NSPoint, c2: NSPoint) -> NSBezierPath {
        let p = NSBezierPath(); p.move(to: a); p.curve(to: b, controlPoint1: c1, controlPoint2: c2); return p
    }
    private func arcPath(cx: CGFloat, cy: CGFloat, r: CGFloat, a0: CGFloat, a1: CGFloat) -> NSBezierPath {
        let p = NSBezierPath(); p.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: a0, endAngle: a1); return p
    }
    private func zigzag(cx: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat, steps: Int) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx - w/2, y: top))
        let dy = h / CGFloat(steps)
        for i in 0..<steps {
            let y = top - dy*CGFloat(i) - dy/2
            p.line(to: NSPoint(x: cx + (i % 2 == 0 ? w/2 : -w/2), y: y))
        }
        return p
    }
}

/// A Siri-style floating window — transparent background so Sumo simply appears on the desktop.
/// Floats above everything, never takes focus, passes clicks through.
final class HUDWindowController {
    private let panel: NSPanel
    private let sumo = SumoView(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
    private let statusLabel = NSTextField(labelWithString: "")
    private let messageLabel: NSTextField
    private var pendingHide: DispatchWorkItem?

    init() {
        let size = NSSize(width: 380, height: 260)
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
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.alphaValue = 0

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]

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
            sumo.widthAnchor.constraint(equalToConstant: 160),
            sumo.heightAnchor.constraint(equalToConstant: 160),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16)
        ])

        panel.contentView = container
    }

    func showListening() { present(status: "Listening…", message: "", pose: .listening) }
    func showThinking(_ command: String) {
        let t = command.trimmingCharacters(in: .whitespacesAndNewlines)
        present(status: "Working on it…", message: t.isEmpty ? "" : "“\(t)”", pose: .thinking)
    }
    func showSpeaking(_ reply: String) {
        present(status: "Sumo", message: reply.trimmingCharacters(in: .whitespacesAndNewlines), pose: .speaking)
    }
    func setLevel(_ level: Float) { sumo.setLevel(level) }

    private func present(status: String, message: String, pose: SumoView.Pose) {
        pendingHide?.cancel(); pendingHide = nil
        statusLabel.stringValue = status
        messageLabel.stringValue = message
        messageLabel.isHidden = message.isEmpty
        sumo.setPose(pose)
        if panel.alphaValue < 0.5 { sumo.playAppear() }
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
        panel.setFrameOrigin(NSPoint(x: visible.midX - s.width / 2, y: visible.minY + 120))
    }
}

/// The menu-bar glyph: a small monochrome Sumo silhouette (a template image, so macOS tints it).
enum JarvisIcon {
    static func sumo() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let w = rect.width, h = rect.height, cx = rect.midX
            NSBezierPath(ovalIn: NSRect(x: cx - w*0.34, y: h*0.10, width: w*0.68, height: h*0.52)).fill()
            NSBezierPath(ovalIn: NSRect(x: cx - w*0.19, y: h*0.50, width: w*0.38, height: h*0.38)).fill()
            NSBezierPath(ovalIn: NSRect(x: cx - w*0.07, y: h*0.82, width: w*0.14, height: h*0.13)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
