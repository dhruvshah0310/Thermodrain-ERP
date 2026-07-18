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

        // ---- System controls ----
        case "set_volume":
            guard config.allowAppleScript, let level = numeric(input["level"]) else {
                return "error: applescript disabled or missing level"
            }
            let clamped = Int(min(max(level, 0), 100))
            let r = runAppleScript("set volume output volume \(clamped)")
            return r.hasPrefix("applescript error") ? r : "volume set to \(clamped)"
        case "get_volume":
            guard config.allowAppleScript else { return "error: applescript disabled" }
            let vol = runAppleScript("output volume of (get volume settings)")
            let muted = runAppleScript("output muted of (get volume settings)")
            return "volume \(vol.trimmingCharacters(in: .whitespacesAndNewlines)), muted: \(muted.trimmingCharacters(in: .whitespacesAndNewlines))"
        case "set_mute":
            guard config.allowAppleScript, let muted = input["muted"] as? Bool else {
                return "error: applescript disabled or missing muted"
            }
            let r = runAppleScript(muted ? "set volume with output muted" : "set volume without output muted")
            return r.hasPrefix("applescript error") ? r : (muted ? "muted" : "unmuted")
        case "adjust_brightness":
            guard config.allowAppleScript, let direction = input["direction"] as? String else {
                return "error: applescript disabled or missing direction"
            }
            let steps = Int(min(max(numeric(input["steps"]) ?? 1, 1), 16))
            // Brightness up = key code 144, down = 145 on most Macs (best-effort).
            let code = direction == "down" ? 145 : 144
            let body = Array(repeating: "key code \(code)", count: steps).joined(separator: "\n")
            let r = runAppleScript(systemEventsScript(action: body, app: nil))
            return r.hasPrefix("applescript error") ? accessibilityHint(r) : "brightness \(direction) x\(steps)"
        case "lock_screen":
            guard config.allowAppleScript else { return "error: applescript disabled" }
            let r = runAppleScript(systemEventsScript(action: "keystroke \"q\" using {command down, control down}", app: nil))
            return r.hasPrefix("applescript error") ? accessibilityHint(r) : "screen locked"
        case "system_sleep":
            guard config.allowAppleScript else { return "error: applescript disabled" }
            let r = runAppleScript("tell application \"System Events\" to sleep")
            return r.hasPrefix("applescript error") ? r : "sleeping"

        // ---- Dedicated app tools ----
        case "control_music":
            guard config.allowAppleScript, let action = input["action"] as? String else {
                return "error: applescript disabled or missing action"
            }
            return controlMusic(action)
        case "add_reminder":
            guard config.allowAppleScript, let text = input["text"] as? String else {
                return "error: applescript disabled or missing text"
            }
            return addReminder(text, due: input["due"] as? String)
        case "create_note":
            guard config.allowAppleScript, let body = input["body"] as? String else {
                return "error: applescript disabled or missing body"
            }
            return createNote(title: input["title"] as? String, body: body)
        case "send_imessage":
            guard config.allowAppleScript, let recipient = input["recipient"] as? String, let text = input["text"] as? String else {
                return "error: applescript disabled or missing recipient/text"
            }
            return sendIMessage(recipient: recipient, text: text)
        case "create_calendar_event":
            guard config.allowAppleScript, let title = input["title"] as? String, let start = input["start"] as? String else {
                return "error: applescript disabled or missing title/start"
            }
            return createCalendarEvent(title: title, start: start, end: input["end"] as? String, calendar: input["calendar"] as? String)
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
        case "read_any_file":
            guard config.allowFullFileAccess, let path = input["path"] as? String else {
                return "error: full file access disabled or missing path"
            }
            return readAnyFile(path)
        case "write_any_file":
            guard config.allowFullFileAccess, let path = input["path"] as? String, let content = input["content"] as? String else {
                return "error: full file access disabled or missing path/content"
            }
            return writeAnyFile(path, content: content)
        case "list_directory":
            guard config.allowFullFileAccess, let path = input["path"] as? String else {
                return "error: full file access disabled or missing path"
            }
            return listDirectory(path)
        case "move_path":
            guard config.allowFullFileAccess, let source = input["source"] as? String, let destination = input["destination"] as? String else {
                return "error: full file access disabled or missing source/destination"
            }
            return movePath(source, destination: destination)
        case "delete_path":
            guard config.allowFullFileAccess, let path = input["path"] as? String else {
                return "error: full file access disabled or missing path"
            }
            return deletePath(path)
        case "open_path":
            guard config.allowFullFileAccess, let path = input["path"] as? String else {
                return "error: full file access disabled or missing path"
            }
            return openPath(path)
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

    // MARK: - Dedicated app tools

    private func controlMusic(_ action: String) -> String {
        let command: String
        switch action {
        case "play": command = "play"
        case "pause": command = "pause"
        case "toggle": command = "playpause"
        case "next": command = "next track"
        case "previous": command = "previous track"
        default: return "error: unknown music action \(action)"
        }
        let r = runAppleScript("tell application \"Music\" to \(command)")
        return r.hasPrefix("applescript error") ? r : "music: \(action)"
    }

    private func addReminder(_ text: String, due: String?) -> String {
        var script = "tell application \"Reminders\"\n"
        if let due, let date = parseISODate(due) {
            script += dateStatements(varName: "dueDate", from: date)
            script += "make new reminder with properties {name:\(appleScriptLiteral(text)), due date:dueDate}\n"
        } else {
            script += "make new reminder with properties {name:\(appleScriptLiteral(text))}\n"
        }
        script += "end tell"
        let r = runAppleScript(script)
        return r.hasPrefix("applescript error") ? r : "reminder added: \(text)"
    }

    private func createNote(title: String?, body: String) -> String {
        // Notes derives the title from the first line of the body.
        let fullBody = (title.map { "\($0)\n" } ?? "") + body
        let script = """
        tell application "Notes"
            make new note with properties {body:\(appleScriptLiteral(fullBody))}
        end tell
        """
        let r = runAppleScript(script)
        return r.hasPrefix("applescript error") ? r : "note created"
    }

    private func sendIMessage(recipient: String, text: String) -> String {
        let script = """
        tell application "Messages"
            set targetService to 1st service whose service type = iMessage
            set targetBuddy to buddy \(appleScriptLiteral(recipient)) of targetService
            send \(appleScriptLiteral(text)) to targetBuddy
        end tell
        """
        let r = runAppleScript(script)
        if r.hasPrefix("applescript error") {
            return r + " (sending iMessage may require the recipient to be reachable via iMessage, and Messages to be signed in)"
        }
        return "message sent to \(recipient) (not verified delivered)"
    }

    private func createCalendarEvent(title: String, start: String, end: String?, calendar: String?) -> String {
        guard let startDate = parseISODate(start) else {
            return "error: could not parse start date '\(start)'. Use ISO 8601 like 2026-07-18T15:00."
        }
        let endDate = end.flatMap { parseISODate($0) } ?? startDate.addingTimeInterval(3600)
        let calTarget = calendar.map { "calendar \(appleScriptLiteral($0))" } ?? "first calendar"
        let script = """
        tell application "Calendar"
        \(dateStatements(varName: "startDate", from: startDate))\(dateStatements(varName: "endDate", from: endDate))    tell \(calTarget)
                make new event with properties {summary:\(appleScriptLiteral(title)), start date:startDate, end date:endDate}
            end tell
        end tell
        """
        let r = runAppleScript(script)
        return r.hasPrefix("applescript error") ? r : "event created: \(title)"
    }

    /// Parse a lenient ISO 8601 string (with or without seconds / timezone) into a Date.
    private func parseISODate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: string) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) { return d }
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = format
            if let d = df.date(from: string) { return d }
        }
        return nil
    }

    /// Emit AppleScript statements that build a named date variable from components, avoiding
    /// locale-dependent `date "…"` string parsing. Day is set to 1 first so setting the month can't
    /// overflow (e.g. current day 31 into a 30-day month). Trailing newline included.
    private func dateStatements(varName: String, from date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let y = c.year ?? 2026, mo = c.month ?? 1, d = c.day ?? 1
        let h = c.hour ?? 0, mi = c.minute ?? 0, s = c.second ?? 0
        return """
            set \(varName) to (current date)
            set day of \(varName) to 1
            set year of \(varName) to \(y)
            set month of \(varName) to \(mo)
            set day of \(varName) to \(d)
            set hours of \(varName) to \(h)
            set minutes of \(varName) to \(mi)
            set seconds of \(varName) to \(s)

        """
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

    /// Blind keystroke tools can't see whether their input landed. When verifyActions is on and screen
    /// control is available, nudge Claude to screenshot and confirm before reporting success (and
    /// retry if it didn't take) — accuracy over speed. No-op otherwise, so it never adds noise when
    /// Claude can't actually see the screen.
    private func verifyHint() -> String {
        guard config.verifyActions, config.allowScreenControl else { return "" }
        return " Take a screenshot to confirm this landed correctly before reporting success, and retry if it didn't."
    }

    private func typeText(_ text: String, app: String?) -> String {
        let result = runAppleScript(systemEventsScript(action: "keystroke \(appleScriptLiteral(text))", app: app))
        if result.hasPrefix("applescript error") {
            return accessibilityHint(result)
        }
        // We can only confirm the keystrokes were dispatched, not that they landed correctly.
        return "dispatched typing of \(text.count) characters (not verified visually)." + verifyHint()
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
        return "pasted \(text.count) characters (not verified visually)." + verifyHint()
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
        return "dispatched key \(key) (not verified visually)." + verifyHint()
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

    // MARK: - Full-disk file access (gated by config.allowFullFileAccess)

    /// Paths that delete_path refuses outright, as a safety net (not a security boundary). Covers the
    /// filesystem root, key system trees, and the user's home root and its top-level Library folders —
    /// deleting any of these would be catastrophic and is never a legitimate voice command.
    private static let protectedDeletePaths: Set<String> = {
        let home = NSHomeDirectory()
        return [
            "/", "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin",
            "/etc", "/var", "/private", "/Users", "/opt", "/cores", "/Volumes",
            home, home + "/Library"
        ]
    }()

    /// Expand a leading ~ and standardize an absolute path. Returns nil for empty input.
    private func absolutePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (trimmed as NSString).expandingTildeInPath
    }

    private func readAnyFile(_ path: String) -> String {
        guard let full = absolutePath(path) else { return "error: empty path" }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir) else {
            return "error: no such file: \(full)"
        }
        if isDir.boolValue { return "error: \(full) is a folder — use list_directory instead" }
        do {
            return try String(contentsOfFile: full, encoding: .utf8)
        } catch {
            return "error: \(error.localizedDescription) (the file may be binary or not UTF-8 text)"
        }
    }

    private func writeAnyFile(_ path: String, content: String) -> String {
        guard let full = absolutePath(path) else { return "error: empty path" }
        let url = URL(fileURLWithPath: full)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "wrote \(content.count) characters to \(full)"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    private func listDirectory(_ path: String) -> String {
        guard let full = absolutePath(path) else { return "error: empty path" }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir) else {
            return "error: no such folder: \(full)"
        }
        guard isDir.boolValue else { return "error: \(full) is a file, not a folder" }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: full) else {
            return "error: could not read \(full) (permission may be denied)"
        }
        if items.isEmpty { return "(empty folder)" }
        // Append a trailing / to subfolders so Claude can tell files from folders.
        let listed = items.sorted().map { name -> String in
            var childIsDir: ObjCBool = false
            let childPath = (full as NSString).appendingPathComponent(name)
            FileManager.default.fileExists(atPath: childPath, isDirectory: &childIsDir)
            return childIsDir.boolValue ? name + "/" : name
        }
        return listed.joined(separator: "\n")
    }

    private func movePath(_ source: String, destination: String) -> String {
        guard let src = absolutePath(source) else { return "error: empty source path" }
        guard let dst = absolutePath(destination) else { return "error: empty destination path" }
        guard FileManager.default.fileExists(atPath: src) else { return "error: no such source: \(src)" }
        let dstURL = URL(fileURLWithPath: dst)
        do {
            try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dst) {
                try FileManager.default.removeItem(atPath: dst)
            }
            try FileManager.default.moveItem(atPath: src, toPath: dst)
            return "moved \(src) → \(dst)"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    private func deletePath(_ path: String) -> String {
        guard let full = absolutePath(path) else { return "error: empty path" }
        let standardized = URL(fileURLWithPath: full).standardizedFileURL.path
        if Self.protectedDeletePaths.contains(standardized) {
            return "blocked: refusing to delete a protected system/home path (\(standardized))"
        }
        guard FileManager.default.fileExists(atPath: full) else { return "error: no such path: \(full)" }
        do {
            try FileManager.default.removeItem(atPath: full)
            return "deleted \(full)"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    private func openPath(_ path: String) -> String {
        guard let full = absolutePath(path) else { return "error: empty path" }
        guard FileManager.default.fileExists(atPath: full) else { return "error: no such path: \(full)" }
        NSWorkspace.shared.open(URL(fileURLWithPath: full))
        return "opened \(full)"
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
