"""'Hey Jarvis' wake word detection.

Uses openWakeWord's pretrained hey_jarvis model — a small ONNX network that
runs comfortably on CPU with ~80 ms chunks, the same approach commercial
assistants use for always-on listening (nothing leaves the machine).

If openWakeWord or its model files are unavailable, Jarvis degrades
gracefully to push-to-talk (hotkey / orb tap) instead of crashing.
"""

from __future__ import annotations

import time

import numpy as np


class WakeWordDetector:
    def __init__(self, threshold: float = 0.5, refractory_s: float = 2.0) -> None:
        self.threshold = threshold
        self.refractory_s = refractory_s
        self._last_fire = 0.0
        self._model = None
        self.available = False
        try:
            from openwakeword.model import Model
            try:
                self._model = Model(wakeword_models=["hey_jarvis"],
                                    inference_framework="onnx")
            except Exception:
                # Model files missing — fetch them, then retry once.
                import openwakeword.utils
                openwakeword.utils.download_models(["hey_jarvis"])
                from openwakeword.model import Model as _Model
                self._model = _Model(wakeword_models=["hey_jarvis"],
                                     inference_framework="onnx")
            self.available = True
        except Exception:
            self._model = None

    def feed(self, chunk: np.ndarray) -> bool:
        """Feed one 80 ms int16 chunk; True when 'hey jarvis' is heard."""
        if self._model is None:
            return False
        try:
            scores = self._model.predict(chunk)
        except Exception:
            return False
        score = max(scores.values()) if scores else 0.0
        now = time.monotonic()
        if score >= self.threshold and (now - self._last_fire) > self.refractory_s:
            self._last_fire = now
            self.reset()
            return True
        return False

    def reset(self) -> None:
        if self._model is not None:
            try:
                self._model.reset()
            except Exception:
                pass
