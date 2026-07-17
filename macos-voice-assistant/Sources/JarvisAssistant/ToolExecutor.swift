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
            return typeText(text)
        case "press_key":
            guard config.allowAppleScript, let key = input["key"] as? String else {
                return "error: applescript disabled or missing key"
            }
            let modifiers = input["modifiers"] as? [String] ?? []
            return pressKey(key, modifiers: modifiers)
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
            return task.terminationStatus == 0 ? "opened \(name)" : "failed to open \(name)"
        } catch {
            return "error: \(error.localizedDescription)"
        }
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

    private func typeText(_ text: String) -> String {
        let script = "tell application \"System Events\" to keystroke \(appleScriptLiteral(text))"
        let result = runAppleScript(script)
        if result.hasPrefix("applescript error") {
            return result + " (this usually means Jarvis needs Accessibility permission: System Settings > Privacy & Security > Accessibility)"
        }
        return "typed \(text.count) characters"
    }

    private func pressKey(_ key: String, modifiers: [String]) -> String {
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
        let result = runAppleScript("tell application \"System Events\" to \(action)")
        if result.hasPrefix("applescript error") {
            return result + " (this usually means Jarvis needs Accessibility permission: System Settings > Privacy & Security > Accessibility)"
        }
        return "pressed \(key)"
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
