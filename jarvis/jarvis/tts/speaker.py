"""Text-to-speech with barge-in.

Sentences are queued and spoken one at a time through macOS `say`, which
means Jarvis starts talking as soon as Claude streams the *first sentence*
instead of waiting for the whole answer — the same trick Google Assistant
uses to feel instant.

`interrupt()` kills the current utterance and clears the queue, so saying
"hey jarvis" (or tapping the orb) mid-answer cuts Jarvis off immediately.

Tip: download a premium voice in System Settings → Accessibility → Spoken
Content (e.g. "Zoe (Premium)" or a Siri voice where available) and set it in
~/.jarvis/config.json for a dramatically better sound than the default.
"""

from __future__ import annotations

import queue
import re
import subprocess
import threading

from ..events import bus

_CLEAN_RE = re.compile(r"[*_`#>|]|\[(.*?)\]\(.*?\)")
_EMOJI_RE = re.compile(
    "[\U0001F300-\U0001FAFF\U00002700-\U000027BF\U0001F000-\U0001F02F"
    "\U00002600-\U000026FF\U0000FE00-\U0000FE0F]+", flags=re.UNICODE)


def _clean_for_speech(text: str) -> str:
    text = _CLEAN_RE.sub(lambda m: m.group(1) or "", text)
    text = _EMOJI_RE.sub("", text)
    return re.sub(r"\s+", " ", text).strip()


class Speaker:
    def __init__(self, voice: str = "", rate: int = 190) -> None:
        self.voice = voice
        self.rate = rate
        self._q: "queue.Queue[str | None]" = queue.Queue()
        self._proc: subprocess.Popen | None = None
        self._lock = threading.Lock()
        self._speaking = threading.Event()
        self._thread = threading.Thread(target=self._worker, daemon=True, name="jarvis-tts")
        self._thread.start()

    # ------------------------------------------------------------------
    def say(self, text: str) -> None:
        text = _clean_for_speech(text)
        if text:
            self._q.put(text)

    def interrupt(self) -> None:
        """Stop talking right now and forget anything queued."""
        try:
            while True:
                self._q.get_nowait()
        except queue.Empty:
            pass
        with self._lock:
            if self._proc is not None and self._proc.poll() is None:
                try:
                    self._proc.kill()
                except Exception:
                    pass

    @property
    def speaking(self) -> bool:
        return self._speaking.is_set() or not self._q.empty()

    def wait_until_done(self, timeout: float | None = None) -> None:
        import time
        deadline = None if timeout is None else time.monotonic() + timeout
        while self.speaking:
            if deadline is not None and time.monotonic() > deadline:
                return
            time.sleep(0.05)

    # ------------------------------------------------------------------
    def _worker(self) -> None:
        while True:
            text = self._q.get()
            if text is None:
                return
            self._speaking.set()
            bus.publish({"type": "speaking", "value": True})
            try:
                cmd = ["say", "-r", str(self.rate)]
                if self.voice:
                    cmd += ["-v", self.voice]
                cmd.append(text)
                with self._lock:
                    self._proc = subprocess.Popen(
                        cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self._proc.wait()
            except Exception:
                pass
            finally:
                with self._lock:
                    self._proc = None
                if self._q.empty():
                    self._speaking.clear()
                    bus.publish({"type": "speaking", "value": False})


class SentenceStreamer:
    """Buffers streamed text deltas and releases whole sentences to the TTS."""

    _BOUNDARY = re.compile(r"(?<=[.!?;:])\s+|\n+")

    def __init__(self, speaker: Speaker) -> None:
        self._speaker = speaker
        self._buf = ""

    def feed(self, delta: str) -> None:
        self._buf += delta
        while True:
            m = self._BOUNDARY.search(self._buf)
            if not m:
                break
            sentence, self._buf = self._buf[:m.start() + 1], self._buf[m.end():]
            if sentence.strip():
                self._speaker.say(sentence)

    def flush(self) -> None:
        if self._buf.strip():
            self._speaker.say(self._buf)
        self._buf = ""
