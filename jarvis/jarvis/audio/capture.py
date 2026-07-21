"""Microphone capture.

Design notes (borrowed from Alexa/Siri front-ends):

- A single always-on 16 kHz mono int16 stream. Consumers pull fixed 80 ms
  chunks from a queue, so wake word, VAD and the recorder all see the same
  timeline.
- A pre-roll ring buffer keeps the last ~600 ms of audio at all times. When
  the wake word fires or the user taps the orb, the recording *starts in the
  past*, so the first syllable is never clipped — the classic failure mode of
  naive voice assistants.
- The stream self-heals: if the device disappears (AirPods disconnect, USB
  mic unplugged) the stream is rebuilt on the default device.
"""

from __future__ import annotations

import collections
import math
import queue
import threading
import time

import numpy as np
import sounddevice as sd


class AudioCapture:
    def __init__(self, sample_rate: int = 16000, chunk_ms: int = 80,
                 preroll_ms: int = 600, device: int | None = None) -> None:
        self.sample_rate = sample_rate
        self.chunk_samples = int(sample_rate * chunk_ms / 1000)
        self.chunk_ms = chunk_ms
        self.device = device
        self.chunks: "queue.Queue[np.ndarray]" = queue.Queue(maxsize=256)
        self._preroll: collections.deque[np.ndarray] = collections.deque(
            maxlen=max(1, preroll_ms // chunk_ms))
        self._level = 0.0
        self._stream: sd.InputStream | None = None
        self._lock = threading.Lock()
        self._running = False

    # ------------------------------------------------------------------
    def start(self) -> None:
        self._running = True
        self._open_stream()

    def stop(self) -> None:
        self._running = False
        with self._lock:
            if self._stream is not None:
                try:
                    self._stream.stop()
                    self._stream.close()
                except Exception:
                    pass
                self._stream = None

    def _open_stream(self) -> None:
        with self._lock:
            if self._stream is not None:
                try:
                    self._stream.stop()
                    self._stream.close()
                except Exception:
                    pass
            self._stream = sd.InputStream(
                samplerate=self.sample_rate,
                channels=1,
                dtype="int16",
                blocksize=self.chunk_samples,
                device=self.device,
                callback=self._callback,
            )
            self._stream.start()

    def _callback(self, indata, frames, time_info, status) -> None:
        chunk = np.frombuffer(bytes(indata), dtype=np.int16).copy()
        # Smoothed RMS level in 0..1 for the UI orb.
        rms = math.sqrt(float(np.mean(chunk.astype(np.float64) ** 2))) / 32768.0
        self._level = 0.7 * self._level + 0.3 * min(1.0, rms * 8.0)
        self._preroll.append(chunk)
        try:
            self.chunks.put_nowait(chunk)
        except queue.Full:
            # Consumer stalled — drop the oldest so we stay realtime.
            try:
                self.chunks.get_nowait()
                self.chunks.put_nowait(chunk)
            except queue.Empty:
                pass

    # ------------------------------------------------------------------
    def read(self, timeout: float = 1.0) -> np.ndarray | None:
        """Next 80 ms chunk, or None on timeout / device loss (auto-recovers)."""
        try:
            return self.chunks.get(timeout=timeout)
        except queue.Empty:
            if self._running:
                # Device probably vanished; rebuild on the default input.
                try:
                    self.device = None
                    self._open_stream()
                except Exception:
                    time.sleep(0.5)
            return None

    def preroll(self) -> np.ndarray:
        """Audio from just before this moment (so the first word isn't lost)."""
        chunks = list(self._preroll)
        if not chunks:
            return np.zeros(0, dtype=np.int16)
        return np.concatenate(chunks)

    @property
    def level(self) -> float:
        return self._level

    @staticmethod
    def list_devices() -> str:
        return str(sd.query_devices())
