"""The floating orb window.

A small, frameless, always-on-top, transparent window rendered with pywebview
(WKWebView on macOS). It shows the animated orb and forwards taps. Runs on the
main thread — macOS requires GUI on the main thread — so the assistant runs in
a background thread and the orchestrator hands control here.

If pywebview isn't available (headless/dev), this degrades to a no-op so the
voice assistant still runs without any UI.
"""

from __future__ import annotations

from pathlib import Path
from typing import Callable

_ORB = Path(__file__).with_name("orb.html")


class _Api:
    def __init__(self, on_tap: Callable[[], None]) -> None:
        self._on_tap = on_tap

    def tap(self) -> None:
        try:
            self._on_tap()
        except Exception:
            pass


def run_window(port: int, on_tap: Callable[[], None]) -> None:
    """Blocking: opens the orb window and runs the GUI loop on this thread."""
    try:
        import webview
    except Exception:
        # No GUI available — block forever so the daemon threads keep running.
        import threading
        threading.Event().wait()
        return

    html = _ORB.read_text().replace(
        "window.JARVIS_PORT || 8971", f"window.JARVIS_PORT || {port}")

    window = webview.create_window(
        "Jarvis",
        html=html,
        width=260, height=260,
        frameless=True,
        easy_drag=True,
        on_top=True,
        transparent=True,
        background_color="#00000000",
        js_api=_Api(on_tap),
    )
    # Park it in the bottom-right by default.
    def _place():
        try:
            import Quartz
            frame = Quartz.CGDisplayBounds(Quartz.CGMainDisplayID())
            w, h = int(frame.size.width), int(frame.size.height)
            window.move(w - 300, h - 340)
        except Exception:
            pass

    webview.start(_place, gui="cocoa", debug=False)
