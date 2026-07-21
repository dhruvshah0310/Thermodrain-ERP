"""Tools that let Claude actually control the Mac.

These are exposed to Claude as tool definitions; when Claude calls one, the
handler runs locally and the result is fed back. Everything here is native
macOS (AppleScript / `osascript`, `open`, shell) so Jarvis can genuinely drive
the laptop: open apps, type, click, set volume, control media, adjust
brightness, run scripts, read the screen, and so on.
"""

from __future__ import annotations

import shlex
import subprocess


def _osascript(script: str) -> str:
    try:
        out = subprocess.run(["osascript", "-e", script], capture_output=True,
                             text=True, timeout=15)
        return (out.stdout or out.stderr).strip()
    except Exception as e:
        return f"error: {e}"


# ----------------------------------------------------------------------
# Tool definitions advertised to Claude.
# ----------------------------------------------------------------------
def tool_specs(allow_shell: bool = True) -> list[dict]:
    specs = [
        {
            "name": "open_app",
            "description": "Open, activate, or switch to a macOS application by name "
                           "(e.g. 'Safari', 'Spotify', 'Visual Studio Code', 'Mail').",
            "input_schema": {
                "type": "object",
                "properties": {"name": {"type": "string", "description": "Application name"}},
                "required": ["name"],
            },
        },
        {
            "name": "open_url",
            "description": "Open a URL, a file path, or a search in the default browser.",
            "input_schema": {
                "type": "object",
                "properties": {"target": {"type": "string",
                               "description": "A URL, file path, or https://www.google.com/search?q=... query URL"}},
                "required": ["target"],
            },
        },
        {
            "name": "set_volume",
            "description": "Set the system output volume (0-100), or mute/unmute.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "level": {"type": "integer", "description": "0-100; omit when muting"},
                    "mute": {"type": "boolean", "description": "true to mute, false to unmute"},
                },
            },
        },
        {
            "name": "set_brightness",
            "description": "Increase or decrease display brightness by a number of steps.",
            "input_schema": {
                "type": "object",
                "properties": {"direction": {"type": "string", "enum": ["up", "down"]},
                               "steps": {"type": "integer", "description": "1-8, default 2"}},
                "required": ["direction"],
            },
        },
        {
            "name": "media_control",
            "description": "Control media playback system-wide (Spotify/Music/browser video): "
                           "play, pause, next track, previous track.",
            "input_schema": {
                "type": "object",
                "properties": {"action": {"type": "string",
                               "enum": ["playpause", "play", "pause", "next", "previous"]}},
                "required": ["action"],
            },
        },
        {
            "name": "system_action",
            "description": "Perform a system action: sleep the display, lock the screen, "
                           "empty trash, take a screenshot, or show a desktop notification.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "action": {"type": "string",
                               "enum": ["sleep", "lock", "empty_trash", "screenshot", "notify"]},
                    "message": {"type": "string", "description": "Text for the notify action"},
                },
                "required": ["action"],
            },
        },
        {
            "name": "type_text",
            "description": "Type text into the currently focused field, as if from the keyboard.",
            "input_schema": {
                "type": "object",
                "properties": {"text": {"type": "string"}},
                "required": ["text"],
            },
        },
        {
            "name": "get_screen_text",
            "description": "Read the title of the frontmost app/window and the current clipboard, "
                           "so you know what the user is looking at.",
            "input_schema": {"type": "object", "properties": {}},
        },
    ]
    if allow_shell:
        specs.append({
            "name": "run_shell",
            "description": "Run a shell command on the Mac and return its output. Use for file "
                           "operations, launching CLIs, git, brew, opening folders, etc. Prefer "
                           "the dedicated tools above when one fits.",
            "input_schema": {
                "type": "object",
                "properties": {"command": {"type": "string"}},
                "required": ["command"],
            },
        })
    return specs


# ----------------------------------------------------------------------
# Handlers.
# ----------------------------------------------------------------------
class MacTools:
    def __init__(self, allow_shell: bool = True, shell_timeout_s: int = 30) -> None:
        self.allow_shell = allow_shell
        self.shell_timeout_s = shell_timeout_s

    def run(self, name: str, args: dict) -> str:
        handler = getattr(self, f"_{name}", None)
        if handler is None:
            return f"Unknown tool: {name}"
        try:
            return handler(args)
        except Exception as e:
            return f"error running {name}: {e}"

    def _open_app(self, args) -> str:
        name = args["name"]
        _osascript(f'tell application "{name}" to activate')
        return f"Opened {name}."

    def _open_url(self, args) -> str:
        subprocess.run(["open", args["target"]], timeout=10)
        return f"Opened {args['target']}."

    def _set_volume(self, args) -> str:
        if args.get("mute") is True:
            _osascript("set volume with output muted")
            return "Muted."
        if args.get("mute") is False:
            _osascript("set volume without output muted")
        if "level" in args and args["level"] is not None:
            lvl = max(0, min(100, int(args["level"])))
            _osascript(f"set volume output volume {lvl}")
            return f"Volume set to {lvl}%."
        return "Done."

    def _set_brightness(self, args) -> str:
        steps = int(args.get("steps", 2))
        key = 144 if args["direction"] == "up" else 145  # F1/F2 brightness keys
        for _ in range(max(1, min(8, steps))):
            _osascript(f'tell application "System Events" to key code {key}')
        return f"Brightness {args['direction']}."

    def _media_control(self, args) -> str:
        action = args["action"]
        keymap = {"playpause": 16, "play": 16, "pause": 16, "next": 17, "previous": 18}
        _osascript(f'tell application "System Events" to key code {keymap[action]}')
        return f"Media: {action}."

    def _system_action(self, args) -> str:
        action = args["action"]
        if action == "sleep":
            _osascript('tell application "System Events" to sleep')
            return "Sleeping the display."
        if action == "lock":
            subprocess.run(["pmset", "displaysleepnow"])
            return "Locked."
        if action == "empty_trash":
            _osascript('tell application "Finder" to empty trash')
            return "Trash emptied."
        if action == "screenshot":
            path = subprocess.run(["mktemp", "/tmp/jarvis-XXXX.png"],
                                  capture_output=True, text=True).stdout.strip()
            subprocess.run(["screencapture", "-x", path])
            return f"Screenshot saved to {path}."
        if action == "notify":
            msg = args.get("message", "Jarvis")
            _osascript(f'display notification "{msg}" with title "Jarvis"')
            return "Notified."
        return "Unknown action."

    def _type_text(self, args) -> str:
        text = args["text"].replace('"', '\\"')
        _osascript(f'tell application "System Events" to keystroke "{text}"')
        return "Typed."

    def _get_screen_text(self, args) -> str:
        front = _osascript(
            'tell application "System Events" to get name of first application process '
            'whose frontmost is true')
        clip = subprocess.run(["pbpaste"], capture_output=True, text=True).stdout[:500]
        return f"Frontmost app: {front}. Clipboard: {clip!r}"

    def _run_shell(self, args) -> str:
        if not self.allow_shell:
            return "Shell access is disabled."
        cmd = args["command"]
        try:
            out = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                                 timeout=self.shell_timeout_s)
            result = (out.stdout + out.stderr).strip()
            return result[:4000] if result else f"(exit {out.returncode}, no output)"
        except subprocess.TimeoutExpired:
            return "Command timed out."
