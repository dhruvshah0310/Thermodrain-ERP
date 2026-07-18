import AppKit
import WebKit

enum SumoPose { case listening, thinking, speaking }

/// Hosts the 3D particle-Sumo (Three.js / WebGL) in a transparent WKWebView, so it simply appears on
/// the desktop when Jarvis wakes. The scene is static (no motion) by request. Three.js is loaded from
/// a CDN — the app already needs the network for Claude — so if the Mac is offline the particles
/// won't load (the labels below still work).
final class SumoWebView: NSView {
    private let webView: WKWebView

    override init(frame frameRect: NSRect) {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: frameRect)
        wantsLayer = true

        webView.translatesAutoresizingMaskIntoConstraints = false
        // Transparent background so only the glowing particles show over the desktop.
        webView.setValue(false, forKey: "drawsBackground")
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://sumo.local/"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // The scene is static, so pose/level/appear are intentionally no-ops (kept for a stable API).
    func setPose(_ pose: SumoPose) {}
    func setLevel(_ level: Float) {}
    func playAppear() {}

    /// Force a repaint — a WebGL context may not draw while its window is hidden, so we nudge it
    /// each time the overlay is shown.
    func refresh() {
        webView.evaluateJavaScript("window.__render && window.__render()", completionHandler: nil)
    }

    /// The user's particle-Sumo scene, adapted for a transparent, static desktop overlay:
    /// working Three.js (r128) CDN, alpha renderer, no fog/grid/controls, no animation.
    private static let html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
      html,body { margin:0; height:100%; overflow:hidden; background:transparent; }
      canvas { display:block; }
    </style>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
    </head>
    <body>
    <script>
      if (window.THREE) {
        const scene = new THREE.Scene();
        const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.1, 1000);
        camera.position.set(0, 4, 16);
        camera.lookAt(0, 4, 0);

        const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
        renderer.setSize(window.innerWidth, window.innerHeight);
        renderer.setPixelRatio(window.devicePixelRatio);
        renderer.setClearColor(0x000000, 0); // transparent
        document.body.appendChild(renderer.domElement);

        const particleCount = 45000;
        const geometry = new THREE.BufferGeometry();
        const positions = new Float32Array(particleCount * 3);
        const colors = new Float32Array(particleCount * 3);
        const colorCore = new THREE.Color('#e06600');
        const colorSkin = new THREE.Color('#ffcc99');
        const colorShadow = new THREE.Color('#331a00');
        let index = 0;

        for (let i = 0; i < particleCount; i++) {
          let x = 0, y = 0, z = 0;
          let mixedColor = colorSkin;
          const randType = Math.random();
          if (randType < 0.35) {
            const u = Math.random(), v = Math.random();
            const theta = u * 2.0 * Math.PI;
            const phi = Math.acos(2.0 * v - 1.0);
            const rX = 2.4 + Math.random() * 0.4;
            const rY = 2.0 + Math.random() * 0.3;
            const rZ = 2.2 + Math.random() * 0.4;
            x = rX * Math.sin(phi) * Math.cos(theta);
            y = rY * Math.cos(phi) + 4.5;
            z = rZ * Math.sin(phi) * Math.sin(theta);
            mixedColor = colorCore.clone().lerp(colorSkin, Math.random() * 0.6);
          } else if (randType < 0.70) {
            const side = Math.random() < 0.5 ? -1 : 1;
            const t = Math.random() * Math.PI;
            x = side * (2.5 + Math.sin(t) * 1.8 + (Math.random() - 0.5) * 0.6);
            y = Math.cos(t) * 2.0 + 2.0 + (Math.random() - 0.5) * 0.6;
            z = Math.sin(t) * 1.2 + (Math.random() - 0.5) * 0.8;
            mixedColor = colorSkin.clone().lerp(colorShadow, Math.random() * 0.4);
          } else if (randType < 0.90) {
            const side = Math.random() < 0.5 ? -1 : 1;
            const progress = Math.random();
            x = side * (2.0 - progress * 0.8) + (Math.random() - 0.5) * 0.4;
            y = (5.5 - progress * 3.5) + (Math.random() - 0.5) * 0.4;
            z = 1.5 + Math.sin(progress * Math.PI) * 0.5 + (Math.random() - 0.5) * 0.4;
            mixedColor = colorSkin;
          } else {
            const theta = Math.random() * 2.0 * Math.PI;
            const phi = Math.acos(2.0 * Math.random() - 1.0);
            const r = 0.8 + Math.random() * 0.2;
            x = r * Math.sin(phi) * Math.cos(theta);
            y = r * Math.cos(phi) + 7.2;
            z = r * Math.sin(phi) * Math.sin(theta) - 0.1;
            mixedColor = (y > 7.6) ? new THREE.Color('#111111') : colorSkin;
          }
          positions[index] = x; positions[index + 1] = y; positions[index + 2] = z;
          colors[index] = mixedColor.r; colors[index + 1] = mixedColor.g; colors[index + 2] = mixedColor.b;
          index += 3;
        }
        geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
        geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));

        const createParticleTexture = () => {
          const canvas = document.createElement('canvas');
          canvas.width = 16; canvas.height = 16;
          const c = canvas.getContext('2d');
          const grad = c.createRadialGradient(8, 8, 0, 8, 8, 8);
          grad.addColorStop(0, 'rgba(255,255,255,1)');
          grad.addColorStop(1, 'rgba(255,255,255,0)');
          c.fillStyle = grad; c.fillRect(0, 0, 16, 16);
          return new THREE.CanvasTexture(canvas);
        };
        const material = new THREE.PointsMaterial({
          size: 0.08, map: createParticleTexture(), vertexColors: true,
          transparent: true, blending: THREE.AdditiveBlending, depthWrite: false
        });
        const particleSystem = new THREE.Points(geometry, material);
        scene.add(particleSystem);

        // Static: render once, and again only on resize or when the overlay reappears.
        function render() {
          if (window.innerWidth > 0) { renderer.setSize(window.innerWidth, window.innerHeight); }
          renderer.render(scene, camera);
        }
        window.__render = render;
        render();
        window.addEventListener('resize', () => {
          camera.aspect = window.innerWidth / window.innerHeight;
          camera.updateProjectionMatrix();
          renderer.setSize(window.innerWidth, window.innerHeight);
          render();
        });
      }
    </script>
    </body>
    </html>
    """
}

/// A Siri-style floating window — transparent background so Sumo simply appears on the desktop.
/// Floats above everything, never takes focus, passes clicks through.
final class HUDWindowController {
    private let panel: NSPanel
    private let sumo = SumoWebView(frame: NSRect(x: 0, y: 0, width: 240, height: 240))
    private let statusLabel = NSTextField(labelWithString: "")
    private let messageLabel: NSTextField
    private var pendingHide: DispatchWorkItem?

    init() {
        let size = NSSize(width: 400, height: 340)
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
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            sumo.widthAnchor.constraint(equalToConstant: 240),
            sumo.heightAnchor.constraint(equalToConstant: 240),
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

    private func present(status: String, message: String, pose: SumoPose) {
        pendingHide?.cancel(); pendingHide = nil
        statusLabel.stringValue = status
        messageLabel.stringValue = message
        messageLabel.isHidden = message.isEmpty
        sumo.setPose(pose)
        positionPanel()
        panel.orderFrontRegardless()
        sumo.refresh()  // WebGL may need a nudge to paint once the window is on screen
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
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
        panel.setFrameOrigin(NSPoint(x: visible.midX - s.width / 2, y: visible.minY + 110))
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
