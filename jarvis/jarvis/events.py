"""A tiny thread-safe event bus.

The assistant publishes state changes ("listening", "thinking", mic level,
transcripts, replies) and the UI websocket server relays them to the orb.
"""

from __future__ import annotations

import threading
from typing import Any, Callable

Handler = Callable[[dict[str, Any]], None]


class EventBus:
    def __init__(self) -> None:
        self._handlers: list[Handler] = []
        self._lock = threading.Lock()

    def subscribe(self, handler: Handler) -> None:
        with self._lock:
            self._handlers.append(handler)

    def publish(self, event: dict[str, Any]) -> None:
        with self._lock:
            handlers = list(self._handlers)
        for h in handlers:
            try:
                h(event)
            except Exception:
                pass  # a broken subscriber must never take down the pipeline


bus = EventBus()
