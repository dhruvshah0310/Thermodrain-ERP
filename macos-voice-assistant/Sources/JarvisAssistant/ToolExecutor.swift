import AppKit
import CoreGraphics
import Foundation

/// The outcome of a tool call. Most tools return plain `text`; screen-capture tools also attach a
/// base64 PNG so Claude can actually see the screen.
struct ToolResult {
    let text: String
    let imageBase64: String?
    let imageMediaType: String?

    init(text: String, imageBase64: String? = nil, imageMediaType: String? = nil) {
        self.text = text
        self.imageBase64 = imageBase64
        self.imageMediaType = imageMediaType
    }
}

/// Executes tool calls Claude asks for. Runs as an actor since Process/NSAppleScript work is
/// blocking and calls arrive from the async Claude conversation loop.
actor ToolExecutor {
    let config: Config

    init(config: Config) {
        self.config = config
    }

    private static let deniedShellPatterns: [String] = [
        "rm -rf /", "rm -rf ~", "rm -rf *", ":(){:|:&};:", "mkfs", "dd if=", "> /dev/disk",
        "diskutil eraseDisk", "shutdown", "reboot", "sudo rm", "chmod -R 777 /",
        "curl | sh", "curl | bash", "wget | sh"
    ]

    func execute(name: String, input: [String: Any]) async -> ToolResult {
        Logger.shared.log("Tool call: \(name) \(input)")

        // Screenshot is the one tool that returns an image rather than text.
        if name == "screenshot" {
            let result = captureScreen()
            Logger.shared.log("Tool result: \(result.text)")
            return result
        }

        let text = await perform(name: name, input: input)
        let shown = text.count > 300 ? String(text.prefix(300)) + "…" : text
        Logger.shared.log("Tool result: \(shown)")
        return ToolResult(text: text)
    }

    private func perform(name: String, input: [String: Any]) async -> String {
        switch name {
        case "open_application":
            guard let app = input["name"] as? String else { return "error: missing name" }
            return openApplication(app)
        case "open_url":
            guard let urlString = input["url"] as? String, let url = URL(string: urlString) else {
                return "error: invalid url"
            }
            NSWorkspace.shared.open(url)
            return "opened \(urlString)"
        case "run_applescript":
            guard config.allowAppleScript, let script = input["script"] as? String else {
                return "error: applescript disabled or missing script"
            }
            return runAppleScript(script)
        case "type_text":
            guard config.allowAppleScript, let text = input["text"] as? String else {
                return "error: applescript disabled or missing text"
            }
            return typeText(text, app: input["app"] as? String)
        case "press_key":
            guard config.allowAppleScript, let key = input["key"] as? String else {
                return "error: applescript disabled or missing key"
            }
            let modifiers = input["modifiers"] as? [String] ?? []
            return pressKey(key, modifiers: modifiers, app: input["app"] as? String)
        case "paste_text":
            guard config.allowAppleScript, let text = input["text"] as? String else {
                return "error: applescript disabled or missing text"
            }
            return pasteText(text, app: input["app"] as? String)
        case "click", "double_click", "right_click", "move_mouse":
            guard config.allowScreenControl else { return "error: screen control disabled" }
            guard let x = numeric(input["x"]), let y = numeric(input["y"]) else {
                return "error: missing x/y coordinates"
            }
            return performMouse(name, x: x, y: y)
        case "scroll":
            guard config.allowScreenControl else { return "error: screen control disabled" }
            let dx = numeric(input["dx"]) ?? 0
            let dy = numeric(input["dy"]) ?? 0
            return performScroll(dx: dx, dy: dy)
        case "wait":
            let seconds = min(max((input["seconds"] as? Double) ?? 1.0, 0), 5.0)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return "waited \(seconds)s"
        case "get_screen_context":
            guard config.allowAppleScript else { return "error: applescript disabled" }
            return getScreenContext()
        case "read_clipboard":
            guard config.allowAppleScript else { return "error: applescript disabled" }
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            return text.isEmpty ? "(clipboard is empty or has no text)" : text
        case "set_clipboard":
            guard config.allowAppleScript, let text = input["text"] as? String else {
                return "error: applescript disabled or missing text"
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return "clipboard set (\(text.count) characters)"
        case "read_file":
            guard config.allowFileAccess, let path = input["path"] as? String else {
                return "error: file access disabled or missing path"
            }
            return readWorkspaceFile(path)
        case "write_file":
            guard config.allowFileAccess, let path = input["path"] as? String, let content = input["content"] as? String else {
                return "error: file access disabled or missing path/content"
            }
            return writeWorkspaceFile(path, content: content)
        case "list_workspace_files":
            return listWorkspaceFiles()
        case "run_shell_command":
            guard config.allowShellCommands, let command = input["command"] as? String else {
                return "error: shell commands disabled or missing command"
            }
            return runShell(command)
        default:
            return "error: unknown tool \(name)"
        }
    }

    private func getScreenContext() -> String {
        let script = """
        tell application "System Events"
            set frontApp to name of first application process whose frontmost is true
            set winTitle to ""
            try
                set winTitle to name of front window of (first application process whose frontmost is true)
            end try
        end tell
        return frontApp & " | " & winTitle
        """
        let result = runAppleScript(script)
        if result.hasPrefix("applescript error") {
            return accessibilityHint(result)
        }
        let parts = result.components(separatedBy: " | ")
        let app = parts.first ?? result
        let window = parts.count > 1 ? parts[1] : ""
        if window.isEmpty {
            return "Frontmost app: \(app). (No window title available.)"
        }
        return "Frontmost app: \(app). Front window: \"\(window)\"."
    }

    private func numeric(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    // MARK: - Screen capture

    /// Capture the main display and return it as a base64 PNG, downscaled to the display's logical
    /// point size so that pixel coordinates Claude reads from the image map 1:1 to the point
    /// coordinates the mouse tools use (this avoids the Retina 2x mismatch).
    private func captureScreen() -> ToolResult {
        guard config.allowScreenControl else {
            return ToolResult(text: "error: screen control disabled")
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jarvis-screen-\(UUID().uuidString).png")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-t", "png", tmp.path] // -x = silent
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ToolResult(text: "error: screencapture failed (\(error.localizedDescription)). Jarvis may need Screen Recording permission in System Settings > Privacy & Security.")
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        guard let image = NSImage(contentsOf: tmp) else {
            return ToolResult(text: "error: could not read the screenshot. Grant Screen Recording permission in System Settings > Privacy & Security, then retry.")
        }

        let logicalSize = NSScreen.main?.frame.size ?? image.size
        guard let png = pngData(from: image, targetSize: logicalSize) else {
            return ToolResult(text: "error: could not encode the screenshot")
        }
        let width = Int(logicalSize.width)
        let height = Int(logicalSize.height)
        return ToolResult(
            text: "Screenshot captured. The screen is \(width) points wide and \(height) points tall; coordinates for click/move tools use this same top-left-origin point space.",
            imageBase64: png.base64EncodedString(),
            imageMediaType: "image/png"
        )
    }

    private func pngData(from image: NSImage, targetSize: NSSize) -> Data? {
        let target = NSSize(width: max(1, targetSize.width), height: max(1, targetSize.height))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = target

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Mouse control (CoreGraphics, top-left-origin point coordinates)

    private func performMouse(_ action: String, x: Double, y: Double) -> String {
        let point = CGPoint(x: x, y: y)
        switch action {
        case "move_mouse":
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            return "moved mouse to (\(Int(x)), \(Int(y)))"
        case "click":
            postClick(at: point, button: .left, clickCount: 1)
            return "clicked at (\(Int(x)), \(Int(y)))"
        case "double_click":
            postClick(at: point, button: .left, clickCount: 2)
            return "double-clicked at (\(Int(x)), \(Int(y)))"
        case "right_click":
            postClick(at: point, button: .right, clickCount: 1)
            return "right-clicked at (\(Int(x)), \(Int(y)))"
        default:
            return "error: unknown mouse action \(action)"
        }
    }

    private func postClick(at point: CGPoint, button: CGMouseButton, clickCount: Int) {
        let downType: CGEventType = (button == .left) ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = (button == .left) ? .leftMouseUp : .rightMouseUp
        // Move first so the target app registers the cursor position.
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
        let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: button)
        let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: button)
        down?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        up?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func performScroll(dx: Double, dy: Double) -> String {
        // CGEvent scroll: positive dy scrolls up, negative down (line units).
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
            wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0
        ) else { return "error: could not create scroll event" }
        event.post(tap: .cghidEventTap)
        return "scrolled (dx \(Int(dx)), dy \(Int(dy)))"
    }

    private func openApplication(_ name: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", name]
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return "failed to open \(name)" }
        } catch {
            return "error: \(error.localizedDescription)"
        }
        // `open -a` launches the app but may not bring it fully to the front; an explicit activate
        // makes it the frontmost app so subsequent keystrokes land in it.
        _ = runAppleScript("tell application \(appleScriptLiteral(name)) to activate")
        return "opened and activated \(name)"
    }

    private func runAppleScript(_ script: String) -> String {
        var errorDict: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else {
            return "error: could not parse applescript"
        }
        let output = scriptObject.executeAndReturnError(&errorDict)
        if let errorDict {
            return "applescript error: \(errorDict)"
        }
        return output.stringValue ?? "ok"
    }

    /// Escapes a string so it can be embedded inside an AppleScript double-quoted literal.
    private func appleScriptLiteral(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Wraps a System Events action so it's directed at a specific app (activated first, keystrokes
    /// sent to that process) when `app` is given, or the frontmost app otherwise. Targeting the
    /// process is much more reliable than hoping the right window happens to be focused.
    private func systemEventsScript(action: String, app: String?) -> String {
        if let app, !app.isEmpty {
            let a = appleScriptLiteral(app)
            return """
            tell application \(a) to activate
            delay 0.4
            tell application "System Events" to tell process \(a) to \(action)
            """
        }
        return "tell application \"System Events\" to \(action)"
    }

    private func accessibilityHint(_ result: String) -> String {
        result + " (if this didn't work, Jarvis likely needs Accessibility permission: System Settings > Privacy & Security > Accessibility — add and enable JarvisAssistant)"
    }

    private func typeText(_ text: String, app: String?) -> String {
        let result = runAppleScript(systemEventsScript(action: "keystroke \(appleScriptLiteral(text))", app: app))
        if result.hasPrefix("applescript error") {
            return accessibilityHint(result)
        }
        // We can only confirm the keystrokes were dispatched, not that they landed correctly.
        return "dispatched typing of \(text.count) characters (not verified visually)"
    }

    private func pasteText(_ text: String, app: String?) -> String {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Small delay so the clipboard write settles before pasting.
        let result = runAppleScript(systemEventsScript(action: "keystroke \"v\" using {command down}", app: app))
        if result.hasPrefix("applescript error") {
            return accessibilityHint(result)
        }
        return "pasted \(text.count) characters (not verified visually)"
    }

    private func pressKey(_ key: String, modifiers: [String], app: String?) -> String {
        let specialKeyCodes: [String: Int] = [
            "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
            "escape": 53, "left": 123, "right": 124, "down": 125, "up": 126
        ]
        let modifierClause: String
        if modifiers.isEmpty {
            modifierClause = ""
        } else {
            let mapped = modifiers.map { "\($0) down" }.joined(separator: ", ")
            modifierClause = " using {\(mapped)}"
        }

        let action: String
        if let code = specialKeyCodes[key.lowercased()] {
            action = "key code \(code)\(modifierClause)"
        } else {
            action = "keystroke \(appleScriptLiteral(key))\(modifierClause)"
        }
        let result = runAppleScript(systemEventsScript(action: action, app: app))
        if result.hasPrefix("applescript error") {
            return accessibilityHint(result)
        }
        return "dispatched key \(key) (not verified visually)"
    }

    private func workspaceURL(for relativePath: String) -> URL? {
        let base = config.workspaceURL.standardizedFileURL
        let candidate = base.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path == base.path || candidate.path.hasPrefix(base.path + "/") else { return nil }
        return candidate
    }

    private func readWorkspaceFile(_ path: String) -> String {
        guard let url = workspaceURL(for: path) else { return "error: path escapes workspace" }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    private func writeWorkspaceFile(_ path: String, content: String) -> String {
        guard let url = workspaceURL(for: path) else { return "error: path escapes workspace" }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "wrote \(url.lastPathComponent)"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    private func listWorkspaceFiles() -> String {
        let base = config.workspaceURL
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: base.path), !items.isEmpty else {
            return "(empty)"
        }
        return items.joined(separator: "\n")
    }

    private func runShell(_ command: String) -> String {
        let lower = command.lowercased()
        for pattern in Self.deniedShellPatterns where lower.contains(pattern) {
            return "blocked: command matched a denylisted destructive pattern (\(pattern))"
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.isEmpty ? "(no output, exit \(task.terminationStatus))" : text
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }
}
