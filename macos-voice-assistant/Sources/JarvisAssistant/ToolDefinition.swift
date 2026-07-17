import Foundation

struct ToolDefinition {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    var jsonSchema: [String: Any] {
        ["name": name, "description": description, "input_schema": inputSchema]
    }
}

enum JarvisTools {
    static func allTools(config: Config) -> [ToolDefinition] {
        var tools: [ToolDefinition] = []

        if config.allowOpenApps {
            tools.append(ToolDefinition(
                name: "open_application",
                description: "Open or activate a macOS application by name, e.g. 'Safari', 'Music', 'Calendar'.",
                inputSchema: [
                    "type": "object",
                    "properties": ["name": ["type": "string", "description": "Application name as it appears in /Applications"]],
                    "required": ["name"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "open_url",
                description: "Open a URL in the default web browser.",
                inputSchema: [
                    "type": "object",
                    "properties": ["url": ["type": "string"]],
                    "required": ["url"]
                ]
            ))
        }

        if config.allowAppleScript {
            tools.append(ToolDefinition(
                name: "run_applescript",
                description: """
                Run an AppleScript snippet to control Mac apps and system settings (Calendar, \
                Reminders, Music, Notes, Finder, system volume, etc). Use this for anything \
                Siri/Jarvis-like that isn't a plain app launch or file operation.
                """,
                inputSchema: [
                    "type": "object",
                    "properties": ["script": ["type": "string", "description": "The AppleScript source to execute"]],
                    "required": ["script"]
                ]
            ))
        }

        if config.allowFileAccess {
            tools.append(ToolDefinition(
                name: "read_file",
                description: "Read a text file from the Jarvis workspace folder (\(config.workspaceDirectory)).",
                inputSchema: [
                    "type": "object",
                    "properties": ["path": ["type": "string", "description": "Path relative to the workspace folder"]],
                    "required": ["path"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "write_file",
                description: "Write or overwrite a text file in the Jarvis workspace folder.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string"],
                        "content": ["type": "string"]
                    ],
                    "required": ["path", "content"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "list_workspace_files",
                description: "List files in the Jarvis workspace folder.",
                inputSchema: ["type": "object", "properties": [String: Any]()]
            ))
        }

        if config.allowShellCommands {
            tools.append(ToolDefinition(
                name: "run_shell_command",
                description: """
                Run a shell command via zsh and return its output. Only enabled because the user \
                explicitly opted in via config; still blocked for a denylist of obviously \
                destructive patterns (not a security boundary, just a safety net).
                """,
                inputSchema: [
                    "type": "object",
                    "properties": ["command": ["type": "string"]],
                    "required": ["command"]
                ]
            ))
        }

        return tools
    }
}
