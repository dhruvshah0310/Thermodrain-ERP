"""Voice-activity endpointing.

Decides when the user has finished talking, Google-Assistant style:

- WebRTC VAD scores each 10 ms sub-frame of the incoming 80 ms chunks.
- Recording begins with the pre-roll buffer already attached.
- The utterance ends after `trailing_silence_ms` of quiet *after* speech was
  heard, on `max_utterance_s`, or gives up after `no_speech_timeout_s` if the
  user never spoke.
"""

from __future__ import annotations

import numpy as np

try:
    import webrtcvad
except ImportError:  # webrtcvad-wheels installs the same module name
    webrtcvad = None


class Endpointer:
    DONE = "done"
    TIMEOUT = "timeout"
    ACTIVE = "active"

    def __init__(self, sample_rate: int = 16000, aggressiveness: int = 2,
                 trailing_silence_ms: int = 800, no_speech_timeout_s: float = 7.0,
                 max_utterance_s: float = 20.0) -> None:
        self.sample_rate = sample_rate
        self._vad = webrtcvad.Vad(aggressiveness) if webrtcvad else None
        self._sub = int(sample_rate * 0.01)  # 10 ms sub-frame
        self.trailing_silence_ms = trailing_silence_ms
        self.no_speech_timeout_s = no_speech_timeout_s
        self.max_utterance_s = max_utterance_s
        self.reset()

    def reset(self, preroll: np.ndarray | None = None) -> None:
        self._buf: list[np.ndarray] = []
        if preroll is not None and preroll.size:
            self._buf.append(preroll)
        self._elapsed_ms = 0.0
        self._silence_ms = 0.0
        self._heard_speech = False

    def _is_voiced(self, chunk: np.ndarray) -> bool:
        if self._vad is None:
            # Fallback: simple energy gate.
            rms = float(np.sqrt(np.mean(chunk.astype(np.float64) ** 2)))
            return rms > 350.0
        raw = chunk.tobytes()
        voiced = 0
        total = 0
        step = self._sub * 2  # bytes per 10 ms sub-frame
        for i in range(0, len(raw) - step + 1, step):
            total += 1
            try:
                if self._vad.is_speech(raw[i:i + step], self.sample_rate):
                    voiced += 1
            except Exception:
                pass
        return total > 0 and (voiced / total) >= 0.35

    def feed(self, chunk: np.ndarray) -> str:
        """Feed one chunk; returns ACTIVE, DONE (got speech) or TIMEOUT (none)."""
        self._buf.append(chunk)
        chunk_ms = len(chunk) / self.sample_rate * 1000.0
        self._elapsed_ms += chunk_ms

        if self._is_voiced(chunk):
            self._heard_speech = True
            self._silence_ms = 0.0
        else:
            self._silence_ms += chunk_ms

        if self._heard_speech:
            if self._silence_ms >= self.trailing_silence_ms:
                return self.DONE
            if self._elapsed_ms >= self.max_utterance_s * 1000.0:
                return self.DONE
        elif self._elapsed_ms >= self.no_speech_timeout_s * 1000.0:
            return self.TIMEOUT
        return self.ACTIVE

    def audio(self) -> np.ndarray:
        if not self._buf:
            return np.zeros(0, dtype=np.int16)
        return np.concatenate(self._buf)

    @property
    def heard_speech(self) -> bool:
        return self._heard_speech
