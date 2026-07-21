"""Jarvis entry point.

    python -m jarvis            # run with the orb UI
    python -m jarvis --no-ui    # headless (voice only)
    python -m jarvis --devices  # list microphones
    python -m jarvis --config   # print the config file path

Threading model: the assistant, websocket server and hotkey listener all run on
background threads; the orb window owns the main thread (a macOS requirement for
GUI). In --no-ui mode the main thread just parks so the daemons keep running.
"""

from __future__ import annotations

import argparse
import sys
import threading

from .assistant import Assistant
from .config import CONFIG_PATH, Config
from .hotkey import start_hotkey


def main() -> None:
    parser = argparse.ArgumentParser(prog="jarvis", description="Jarvis voice assistant")
    parser.add_argument("--no-ui", action="store_true", help="run without the orb window")
    parser.add_argument("--devices", action="store_true", help="list audio input devices")
    parser.add_argument("--config", action="store_true", help="show config file path")
    args = parser.parse_args()

    if args.devices:
        from .audio.capture import AudioCapture
        print(AudioCapture.list_devices())
        return
    if args.config:
        cfg = Config.load()
        cfg.save()
        print(CONFIG_PATH)
        return

    config = Config.load()
    config.save()  # materialise defaults on first run

    if not config.resolved_api_key():
        print("⚠️  No Anthropic API key found.\n"
              "   Set ANTHROPIC_API_KEY, or add \"api_key\" to", CONFIG_PATH,
              "\n   (Offline skills still work; internet answers need the key.)",
              file=sys.stderr)

    assistant = Assistant(config)
    start_hotkey(config.hotkey, assistant.trigger)

    ui_server = None
    if config.show_ui and not args.no_ui:
        from .ui.server import UIServer
        ui_server = UIServer(config.ui_port, assistant.trigger)
        ui_server.start()

    # Assistant on a background thread; UI (if any) owns the main thread.
    threading.Thread(target=assistant.start, daemon=True, name="jarvis-core").start()

    if config.show_ui and not args.no_ui:
        from .ui.window import run_window
        try:
            run_window(config.ui_port, assistant.trigger)
        except KeyboardInterrupt:
            pass
    else:
        try:
            threading.Event().wait()
        except KeyboardInterrupt:
            pass

    assistant.stop()


if __name__ == "__main__":
    main()
