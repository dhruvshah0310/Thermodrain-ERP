import AppKit
import QuartzCore

/// Iron-Man-style arc-reactor graphic, drawn with Core Animation layers: a glowing core, an outer
/// ring, and a rotating ring of coil segments. It has three "moods" that change color and energy so
/// you can tell at a glance whether Jarvis is listening, thinking, or speaking.
final class ArcReactorView: NSView {
    enum Mood { case listening, thinking, speaking }

    private let glowLayer = CAGradientLayer()
    private let coreLayer = CAGradientLayer()
    private let outerRing = CAShapeLayer()
    private let innerRing = CAShapeLayer()
    private let coils = CAReplicatorLayer()
    private let coilSeed = CAShapeLayer()

    private let coilCount = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        buildLayers()
        setMood(.listening)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        buildLayers()
        setMood(.listening)
    }

    override var isFlipped: Bool { true }

    private func buildLayers() {
        glowLayer.type = .radial
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(glowLayer)

        outerRing.fillColor = NSColor.clear.cgColor
        outerRing.lineWidth = 2
        layer?.addSublayer(outerRing)

        coilSeed.lineCap = .round
        coils.instanceCount = coilCount
        coils.addSublayer(coilSeed)
        layer?.addSublayer(coils)

        innerRing.fillColor = NSColor.clear.cgColor
        innerRing.lineWidth = 1.5
        layer?.addSublayer(innerRing)

        coreLayer.type = .radial
        coreLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        coreLayer.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(coreLayer)

        addRotation()
        addPulse()
    }

    override func layout() {
        super.layout()
        let b = bounds
        let center = CGPoint(x: b.midX, y: b.midY)
        let r = min(b.width, b.height) / 2

        glowLayer.frame = b.insetBy(dx: -r * 0.4, dy: -r * 0.4)
        glowLayer.cornerRadius = glowLayer.frame.width / 2

        outerRing.frame = b
        outerRing.path = CGPath(ellipseIn: b.insetBy(dx: r * 0.06, dy: r * 0.06), transform: nil)

        innerRing.frame = b
        innerRing.path = CGPath(ellipseIn: b.insetBy(dx: r * 0.52, dy: r * 0.52), transform: nil)

        // Coil ring: one short segment near the top, replicated in a circle about the center.
        coils.frame = b
        coils.instanceCount = coilCount
        coils.instanceTransform = CATransform3DMakeRotation(2 * .pi / CGFloat(coilCount), 0, 0, 1)
        coilSeed.frame = b
        let segW = r * 0.14
        let segTop = r * 0.16
        let segBottom = r * 0.42
        let seg = CGMutablePath()
        seg.addRoundedRect(
            in: CGRect(x: center.x - segW / 2, y: segTop, width: segW, height: segBottom - segTop),
            cornerWidth: segW / 2, cornerHeight: segW / 2
        )
        coilSeed.path = seg

        let coreInset = r * 0.66
        coreLayer.frame = b.insetBy(dx: coreInset, dy: coreInset)
        coreLayer.cornerRadius = coreLayer.frame.width / 2
    }

    private func addRotation() {
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = 8
        spin.repeatCount = .infinity
        coils.add(spin, forKey: "spin")
    }

    private func addPulse() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.86
        scale.toValue = 1.06
        scale.duration = 1.4
        scale.autoreverses = true
        scale.repeatCount = .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        coreLayer.add(scale, forKey: "pulse")

        let glow = CABasicAnimation(keyPath: "opacity")
        glow.fromValue = 0.45
        glow.toValue = 0.9
        glow.duration = 1.4
        glow.autoreverses = true
        glow.repeatCount = .infinity
        glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(glow, forKey: "breathe")
    }

    /// Switch color palette + energy for the current activity. `layer.speed` scales the running
    /// spin/pulse animations smoothly without having to rebuild them.
    func setMood(_ mood: Mood) {
        let tint: NSColor
        let speed: Float
        switch mood {
        case .listening: tint = NSColor(calibratedRed: 0.36, green: 0.80, blue: 1.0, alpha: 1); speed = 1.0
        case .thinking:  tint = NSColor(calibratedRed: 0.42, green: 0.90, blue: 1.0, alpha: 1); speed = 2.2
        case .speaking:  tint = NSColor(calibratedRed: 0.30, green: 0.70, blue: 1.0, alpha: 1); speed = 1.5
        }

        let bright = tint.blended(withFraction: 0.55, of: .white) ?? tint

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outerRing.strokeColor = tint.withAlphaComponent(0.9).cgColor
        outerRing.shadowColor = tint.cgColor
        outerRing.shadowRadius = 8
        outerRing.shadowOpacity = 0.9
        outerRing.shadowOffset = .zero
        innerRing.strokeColor = bright.withAlphaComponent(0.85).cgColor
        coilSeed.fillColor = tint.withAlphaComponent(0.95).cgColor
        coilSeed.strokeColor = NSColor.clear.cgColor
        coilSeed.shadowColor = tint.cgColor
        coilSeed.shadowRadius = 4
        coilSeed.shadowOpacity = 0.8
        coilSeed.shadowOffset = .zero
        coreLayer.colors = [bright.cgColor, tint.withAlphaComponent(0.7).cgColor, tint.withAlphaComponent(0.0).cgColor]
        coreLayer.locations = [0, 0.5, 1]
        glowLayer.colors = [tint.withAlphaComponent(0.55).cgColor, tint.withAlphaComponent(0.0).cgColor]
        glowLayer.locations = [0, 1]
        coils.speed = speed
        coreLayer.speed = speed
        glowLayer.speed = speed
        CATransaction.commit()
    }
}

/// A Siri-style floating window: a rounded, blurred panel holding the arc reactor plus a status line
/// and the current command / reply text. It floats above everything, never takes focus, and passes
/// mouse clicks through, so it behaves like a heads-up overlay rather than a real window.
final class HUDWindowController {
    private let panel: NSPanel
    private let reactor = ArcReactorView(frame: NSRect(x: 0, y: 0, width: 104, height: 104))
    private let statusLabel = NSTextField(labelWithString: "")
    private let messageLabel: NSTextField
    private var pendingHide: DispatchWorkItem?

    init() {
        let size = NSSize(width: 360, height: 220)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.alphaValue = 0

        let visual = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 24
        visual.layer?.masksToBounds = true
        visual.autoresizingMask = [.width, .height]

        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center

        messageLabel = NSTextField(wrappingLabelWithString: "")
        messageLabel.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        messageLabel.textColor = .labelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.preferredMaxLayoutWidth = size.width - 48

        reactor.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [reactor, statusLabel, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(stack)

        NSLayoutConstraint.activate([
            reactor.widthAnchor.constraint(equalToConstant: 104),
            reactor.heightAnchor.constraint(equalToConstant: 104),
            stack.centerXAnchor.constraint(equalTo: visual.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: visual.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: visual.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: visual.trailingAnchor, constant: -24)
        ])

        panel.contentView = visual
    }

    // MARK: - State transitions (call on the main thread)

    func showListening() {
        present(status: "Listening…", message: "", mood: .listening)
    }

    func showThinking(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        present(status: "Working on it…", message: trimmed.isEmpty ? "" : "“\(trimmed)”", mood: .thinking)
    }

    func showSpeaking(_ reply: String) {
        present(status: "Jarvis", message: reply.trimmingCharacters(in: .whitespacesAndNewlines), mood: .speaking)
    }

    private func present(status: String, message: String, mood: ArcReactorView.Mood) {
        pendingHide?.cancel()
        pendingHide = nil
        statusLabel.stringValue = status
        messageLabel.stringValue = message
        messageLabel.isHidden = message.isEmpty
        reactor.setMood(mood)
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
        let y = visible.minY + 130  // hover near the bottom, like Siri
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// The menu-bar glyph: a small monochrome arc-reactor (a template image, so macOS tints it to match
/// the menu bar). Used for the idle state so Jarvis reads as an Iron-Man-style reactor at a glance.
enum JarvisIcon {
    static func reactor() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            let center = NSPoint(x: rect.midX, y: rect.midY)

            let outer = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            outer.lineWidth = 1.4
            outer.stroke()

            let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 5.5, dy: 5.5))
            inner.lineWidth = 1.1
            inner.stroke()

            // Spokes between the two rings.
            let rIn = (rect.width / 2) - 5.5
            let rOut = (rect.width / 2) - 1.5
            for i in 0..<6 {
                let a = CGFloat(i) * (.pi / 3)
                let p1 = NSPoint(x: center.x + rIn * cos(a), y: center.y + rIn * sin(a))
                let p2 = NSPoint(x: center.x + rOut * cos(a), y: center.y + rOut * sin(a))
                let spoke = NSBezierPath()
                spoke.move(to: p1)
                spoke.line(to: p2)
                spoke.lineWidth = 1.0
                spoke.stroke()
            }

            // Reactor core triangle.
            let tri = NSBezierPath()
            let rc: CGFloat = 2.6
            for i in 0..<3 {
                let a = CGFloat(i) * (2 * .pi / 3) - .pi / 2
                let p = NSPoint(x: center.x + rc * cos(a), y: center.y + rc * sin(a))
                if i == 0 { tri.move(to: p) } else { tri.line(to: p) }
            }
            tri.close()
            tri.lineWidth = 1.0
            tri.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
