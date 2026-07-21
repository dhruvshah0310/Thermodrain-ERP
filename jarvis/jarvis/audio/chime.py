"""Short earcons so you know when Jarvis is listening.

Plays the built-in macOS system sounds via `afplay` — no assets to ship, and
they match the OS aesthetic. Silent no-op if the files are missing.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

_SOUNDS = {
    "wake": "/System/Library/Sounds/Tink.aiff",     # "I'm listening"
    "accept": "/System/Library/Sounds/Pop.aiff",     # "got it, thinking"
    "cancel": "/System/Library/Sounds/Bottle.aiff",  # "never mind"
}


def play(kind: str, enabled: bool = True) -> None:
    if not enabled:
        return
    path = _SOUNDS.get(kind)
    if not path or not Path(path).exists():
        return
    try:
        subprocess.Popen(["afplay", path],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
