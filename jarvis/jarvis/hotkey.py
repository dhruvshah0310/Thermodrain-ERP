"""Global push-to-talk hotkey (default ⌥Space).

Works even when the wake word is disabled or a mic is unavailable, and lets you
barge in while Jarvis is speaking. Requires macOS Accessibility permission for
the terminal/app running Jarvis. No-op if pynput is missing.
"""

from __future__ import annotations

import threading
from typing import Callable


def start_hotkey(combo: str, on_press: Callable[[], None]) -> None:
    try:
        from pynput import keyboard
    except Exception:
        return

    def _run():
        try:
            with keyboard.GlobalHotKeys({combo: on_press}) as h:
                h.join()
        except Exception:
            pass

    threading.Thread(target=_run, daemon=True, name="jarvis-hotkey").start()
