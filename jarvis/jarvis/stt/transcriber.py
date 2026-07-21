"""Speech-to-text via faster-whisper.

Runs Whisper locally (CTranslate2, int8) so transcription works offline and
audio never leaves the machine. base.en transcribes a typical command in well
under a second on Apple Silicon; bump to small.en in config for accuracy.
"""

from __future__ import annotations

import threading

import numpy as np


class Transcriber:
    def __init__(self, model_name: str = "base.en", compute_type: str = "int8",
                 language: str = "en") -> None:
        self.model_name = model_name
        self.compute_type = compute_type
        self.language = language
        self._model = None
        self._lock = threading.Lock()

    def warm_up(self) -> None:
        """Load the model ahead of time so the first command isn't slow."""
        self._ensure_model()

    def _ensure_model(self):
        with self._lock:
            if self._model is None:
                from faster_whisper import WhisperModel
                self._model = WhisperModel(self.model_name, device="cpu",
                                           compute_type=self.compute_type)
        return self._model

    def transcribe(self, audio_int16: np.ndarray) -> str:
        if audio_int16.size == 0:
            return ""
        model = self._ensure_model()
        audio = audio_int16.astype(np.float32) / 32768.0
        segments, _info = model.transcribe(
            audio,
            language=self.language if self.language != "auto" else None,
            beam_size=1,
            condition_on_previous_text=False,
        )
        text = " ".join(seg.text.strip() for seg in segments).strip()
        # Whisper hallucinates filler on pure silence; drop the classics.
        if text.lower().strip(" .!?") in {"", "you", "thank you", "thanks for watching",
                                          "bye", "the end", "silence"}:
            if audio_int16.size < self._min_speech_samples():
                return ""
        return text

    def _min_speech_samples(self) -> int:
        return 16000  # 1 second
