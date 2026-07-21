"""Websocket bridge between the assistant and the orb.

The assistant publishes events on the in-process bus; this server relays them
to the orb (state, mic level, captions) and forwards the orb's "tap" back to
the assistant as a push-to-talk trigger. Runs its own asyncio loop in a thread
so it never blocks audio.
"""

from __future__ import annotations

import asyncio
import json
import threading
from typing import Callable

from ..events import bus


class UIServer:
    def __init__(self, port: int, on_tap: Callable[[], None]) -> None:
        self.port = port
        self._on_tap = on_tap
        self._clients: set = set()
        self._loop: asyncio.AbstractEventLoop | None = None
        self._thread = threading.Thread(target=self._run, daemon=True, name="jarvis-ui")

    def start(self) -> None:
        bus.subscribe(self._on_bus_event)
        self._thread.start()

    def _on_bus_event(self, event: dict) -> None:
        # Only forward UI-relevant events.
        if event.get("type") in {"state", "level", "caption", "speaking"}:
            self.broadcast(event)

    def broadcast(self, event: dict) -> None:
        if self._loop is None:
            return
        data = json.dumps(event)
        asyncio.run_coroutine_threadsafe(self._broadcast(data), self._loop)

    async def _broadcast(self, data: str) -> None:
        dead = []
        for ws in list(self._clients):
            try:
                await ws.send(data)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self._clients.discard(ws)

    async def _handler(self, ws) -> None:
        self._clients.add(ws)
        try:
            async for raw in ws:
                try:
                    msg = json.loads(raw)
                except Exception:
                    continue
                if msg.get("type") == "tap":
                    try:
                        self._on_tap()
                    except Exception:
                        pass
        except Exception:
            pass
        finally:
            self._clients.discard(ws)

    def _run(self) -> None:
        import websockets
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)

        async def _serve():
            async with websockets.serve(self._handler, "127.0.0.1", self.port):
                await asyncio.Future()

        try:
            self._loop.run_until_complete(_serve())
        except Exception:
            pass
