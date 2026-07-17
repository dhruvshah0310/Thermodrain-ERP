import AppKit
import Foundation

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

    func execute(name: String, input: [String: Any]) async -> String {
        Logger.shared.log("Tool call: \(name) \(input)")
        let result = await perform(name: name, input: input)
        let shown = result.count > 300 ? String(result.prefix(300)) + "…" : result
        Logger.shared.log("Tool result: \(shown)")
        return result
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
        case "wait":
            let seconds = min(max((input["seconds"] as? Double) ?? 1.0, 0), 5.0)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return "waited \(seconds)s"
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
