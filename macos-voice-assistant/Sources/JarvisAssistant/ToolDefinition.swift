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
                Reminders, Music, Notes, Mail, Finder, system volume, etc). Use this for anything \
                Siri/Jarvis-like that isn't a plain app launch or file operation. For apps that \
                aren't directly scriptable (like WhatsApp), drive their UI with System Events, or \
                use the type_text / press_key tools.
                """,
                inputSchema: [
                    "type": "object",
                    "properties": ["script": ["type": "string", "description": "The AppleScript source to execute"]],
                    "required": ["script"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "type_text",
                description: """
                Type a string into whatever app is frontmost, as if typed on the keyboard (via \
                System Events). Use it to fill in a message box, a search field, an email body, \
                etc. Make sure the right app/field is focused first (open_application or open_url). \
                Requires macOS Accessibility permission for Jarvis.
                """,
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "The text to type"],
                        "app": ["type": "string", "description": "App name to direct the typing to (e.g. \"WhatsApp\"); it is activated first. Strongly recommended so keystrokes land in the right app. Omit to type into whatever is frontmost."]
                    ],
                    "required": ["text"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "press_key",
                description: """
                Press a single key, optionally with modifiers, in the frontmost app (via System \
                Events) — e.g. press "return" to send a message, or "c" with modifier "command" to \
                copy. Requires macOS Accessibility permission for Jarvis.
                """,
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "key": ["type": "string", "description": "Key to press: a single character, or one of: return, tab, space, delete, escape, up, down, left, right"],
                        "modifiers": [
                            "type": "array",
                            "items": ["type": "string", "enum": ["command", "option", "control", "shift"]],
                            "description": "Optional modifier keys held while pressing"
                        ],
                        "app": ["type": "string", "description": "App name to direct the keypress to (e.g. \"WhatsApp\"); it is activated first. Recommended so the key lands in the right app. Omit for the frontmost app."]
                    ],
                    "required": ["key"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "paste_text",
                description: """
                Put text on the clipboard and paste it (Cmd+V) into an app. More reliable than \
                type_text for long messages, emoji, or special characters. Pass app to direct it \
                to a specific app (recommended).
                """,
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "The text to paste"],
                        "app": ["type": "string", "description": "App name to paste into (e.g. \"WhatsApp\"); activated first. Recommended."]
                    ],
                    "required": ["text"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "wait",
                description: "Pause briefly (e.g. to let an app finish opening before typing into it). Keep it short — a second or two.",
                inputSchema: [
                    "type": "object",
                    "properties": ["seconds": ["type": "number", "description": "How long to wait, in seconds (max 5)"]],
                    "required": ["seconds"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "get_screen_context",
                description: """
                Report what the user is currently looking at: the frontmost app's name and its \
                front window's title. Call this when a command is about "this", "the current \
                window", "what's open", etc., so you know the context before acting.
                """,
                inputSchema: ["type": "object", "properties": [String: Any]()]
            ))
            tools.append(ToolDefinition(
                name: "read_clipboard",
                description: "Read the current text contents of the macOS clipboard.",
                inputSchema: ["type": "object", "properties": [String: Any]()]
            ))
            tools.append(ToolDefinition(
                name: "set_clipboard",
                description: "Replace the macOS clipboard with the given text.",
                inputSchema: [
                    "type": "object",
                    "properties": ["text": ["type": "string", "description": "Text to put on the clipboard"]],
                    "required": ["text"]
                ]
            ))

            // ---- System controls ----
            tools.append(ToolDefinition(
                name: "set_volume",
                description: "Set the Mac's output volume to a level from 0 (silent) to 100 (max).",
                inputSchema: [
                    "type": "object",
                    "properties": ["level": ["type": "number", "description": "Volume 0–100"]],
                    "required": ["level"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "get_volume",
                description: "Get the Mac's current output volume (0–100) and mute state.",
                inputSchema: ["type": "object", "properties": [String: Any]()]
            ))
            tools.append(ToolDefinition(
                name: "set_mute",
                description: "Mute or unmute the Mac's output.",
                inputSchema: [
                    "type": "object",
                    "properties": ["muted": ["type": "boolean", "description": "true to mute, false to unmute"]],
                    "required": ["muted"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "adjust_brightness",
                description: "Nudge display brightness up or down a few steps (best-effort via the brightness keys).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "direction": ["type": "string", "enum": ["up", "down"]],
                        "steps": ["type": "number", "description": "How many key presses (1–16)"]
                    ],
                    "required": ["direction"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "lock_screen",
                description: "Lock the Mac's screen (requires the password/Touch ID to get back in).",
                inputSchema: ["type": "object", "properties": [String: Any]()]
            ))
            tools.append(ToolDefinition(
                name: "system_sleep",
                description: "Put the Mac to sleep.",
                inputSchema: ["type": "object", "properties": [String: Any]()]
            ))

            // ---- Dedicated app tools ----
            tools.append(ToolDefinition(
                name: "control_music",
                description: "Control the Music app: play, pause, toggle (play/pause), next, or previous track.",
                inputSchema: [
                    "type": "object",
                    "properties": ["action": ["type": "string", "enum": ["play", "pause", "toggle", "next", "previous"]]],
                    "required": ["action"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "add_reminder",
                description: "Add a reminder to the Reminders app, with an optional due date/time.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "What to be reminded about"],
                        "due": ["type": "string", "description": "Optional due date/time, ISO 8601 e.g. 2026-07-18T15:00"]
                    ],
                    "required": ["text"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "create_note",
                description: "Create a note in the Notes app.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Optional title (becomes the first line)"],
                        "body": ["type": "string", "description": "Note contents"]
                    ],
                    "required": ["body"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "send_imessage",
                description: "Send an iMessage/SMS to a phone number or email via the Messages app. Confirm the recipient if unsure.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "recipient": ["type": "string", "description": "Phone number (with country code) or email"],
                        "text": ["type": "string", "description": "Message text"]
                    ],
                    "required": ["recipient", "text"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "create_calendar_event",
                description: "Create an event in the Calendar app.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "start": ["type": "string", "description": "Start date/time, ISO 8601 e.g. 2026-07-18T15:00"],
                        "end": ["type": "string", "description": "Optional end (defaults to 1 hour after start)"],
                        "calendar": ["type": "string", "description": "Optional calendar name; defaults to the first calendar"]
                    ],
                    "required": ["title", "start"]
                ]
            ))
        }

        if config.allowScreenControl {
            tools.append(ToolDefinition(
                name: "screenshot",
                description: """
                Capture the current screen and see it. Use this to find out what's on screen before \
                clicking or typing, and to verify an action worked afterward. The returned image is \
                in points with a top-left origin; use those same coordinates for click/move.
                """,
                inputSchema: ["type": "object", "properties": [String: Any]()]
            ))
            tools.append(ToolDefinition(
                name: "click",
                description: "Click the mouse at screen coordinates (points, top-left origin). Take a screenshot first to find the coordinates.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "x": ["type": "number", "description": "X coordinate in points"],
                        "y": ["type": "number", "description": "Y coordinate in points"]
                    ],
                    "required": ["x", "y"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "double_click",
                description: "Double-click at screen coordinates (points, top-left origin).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "x": ["type": "number"], "y": ["type": "number"]
                    ],
                    "required": ["x", "y"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "right_click",
                description: "Right-click (secondary click) at screen coordinates (points, top-left origin).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "x": ["type": "number"], "y": ["type": "number"]
                    ],
                    "required": ["x", "y"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "move_mouse",
                description: "Move the mouse cursor to screen coordinates without clicking (points, top-left origin).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "x": ["type": "number"], "y": ["type": "number"]
                    ],
                    "required": ["x", "y"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "scroll",
                description: "Scroll the mouse wheel. dy positive scrolls up, negative scrolls down; dx scrolls horizontally. Units are lines (a few lines at a time).",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "dx": ["type": "number", "description": "Horizontal scroll (lines)"],
                        "dy": ["type": "number", "description": "Vertical scroll (lines); negative = down"]
                    ]
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

        if config.allowFullFileAccess {
            tools.append(ToolDefinition(
                name: "read_any_file",
                description: """
                Read a text file from anywhere on the Mac. Give an absolute path; a leading ~ is \
                expanded to the home folder (e.g. ~/Documents/notes.txt, /Users/you/Desktop/x.md).
                """,
                inputSchema: [
                    "type": "object",
                    "properties": ["path": ["type": "string", "description": "Absolute or ~-relative path to the file"]],
                    "required": ["path"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "write_any_file",
                description: """
                Write or overwrite a text file anywhere on the Mac (creating parent folders as \
                needed). Absolute or ~-relative path. Overwrites without warning, so double-check \
                the path.
                """,
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "Absolute or ~-relative destination path"],
                        "content": ["type": "string", "description": "Full text contents to write"]
                    ],
                    "required": ["path", "content"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "list_directory",
                description: "List the contents of a folder anywhere on the Mac (names only, with a trailing / on subfolders). Absolute or ~-relative path.",
                inputSchema: [
                    "type": "object",
                    "properties": ["path": ["type": "string", "description": "Absolute or ~-relative folder path"]],
                    "required": ["path"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "move_path",
                description: "Move or rename a file or folder anywhere on the Mac. Both source and destination are absolute or ~-relative paths.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "source": ["type": "string", "description": "Existing file/folder to move"],
                        "destination": ["type": "string", "description": "New path (its parent folders are created if missing)"]
                    ],
                    "required": ["source", "destination"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "delete_path",
                description: """
                Delete a file or folder anywhere on the Mac (permanently — not to the Trash). \
                Critical system and home-root paths are refused as a safety net. Be sure before \
                calling this; confirm with the user first if there's any doubt.
                """,
                inputSchema: [
                    "type": "object",
                    "properties": ["path": ["type": "string", "description": "Absolute or ~-relative path to delete"]],
                    "required": ["path"]
                ]
            ))
            tools.append(ToolDefinition(
                name: "open_path",
                description: "Open a file, folder, or app at a path in its default application (like double-clicking it in Finder). Absolute or ~-relative path.",
                inputSchema: [
                    "type": "object",
                    "properties": ["path": ["type": "string", "description": "Absolute or ~-relative path to open"]],
                    "required": ["path"]
                ]
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

    /// Anthropic-hosted server tools (executed on Anthropic's side, not by us). Currently just web
    /// search, which lets Claude look things up before answering. Declared as raw dictionaries
    /// because their shape (type + name) differs from client tools.
    static func serverTools(config: Config) -> [[String: Any]] {
        var tools: [[String: Any]] = []
        if config.allowWebSearch {
            // The 20260209 variants (with dynamic filtering) are supported by the default
            // claude-sonnet-5 model. Older models would need "web_search_20250305" instead.
            tools.append(["type": "web_search_20260209", "name": "web_search", "max_uses": 5])
            // web_fetch reads the full content of a specific URL already mentioned in the
            // conversation (e.g. a link the user said, or one web_search returned).
            tools.append(["type": "web_fetch_20260209", "name": "web_fetch", "max_uses": 5])
        }
        return tools
    }
}
