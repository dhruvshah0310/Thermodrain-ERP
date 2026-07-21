"""The orchestrator — Jarvis's state machine.

Runs on a background thread and coordinates every piece:

    idle ──(wake word / tap / hotkey)──▶ listening
    listening ──(speech ends)──▶ thinking ──▶ speaking ──▶ (follow-up window) ──▶ idle

Key behaviours that make it feel smooth:

- **Barge-in**: while Jarvis is speaking, the wake word / a tap / the hotkey
  cuts it off instantly and starts listening again.
- **Pre-roll capture**: recording starts ~600 ms in the past so the first word
  is never clipped.
- **Streaming reply**: Claude's text is spoken sentence-by-sentence as it
  streams, and each spoken sentence is also pushed to the orb caption.
- **Follow-up window**: after a reply Jarvis keeps listening briefly so you can
  say "and what about tomorrow?" without repeating the wake word.
- **Offline-first shortcuts**: time, timers, math, volume, app-launch and
  remembered facts are answered locally with zero latency.
"""

from __future__ import annotations

import threading
import time

import numpy as np

from .audio import chime
from .audio.capture import AudioCapture
from .audio.vad import Endpointer
from .audio.wakeword import WakeWordDetector
from .brain.claude_client import ClaudeBrain
from .brain.memory import Memory
from .brain.offline_skills import OfflineSkills
from .events import bus
from .stt.transcriber import Transcriber
from .tts.speaker import SentenceStreamer, Speaker

IDLE, LISTENING, THINKING, SPEAKING = "idle", "listening", "thinking", "speaking"


class Assistant:
    def __init__(self, config) -> None:
        self.config = config
        self.capture = AudioCapture(config.sample_rate, config.chunk_ms,
                                    config.preroll_ms, config.input_device)
        self.wake = WakeWordDetector(config.wake_threshold, config.wake_refractory_s) \
            if config.wake_word_enabled else None
        self.endpointer = Endpointer(config.sample_rate, config.vad_aggressiveness,
                                     config.trailing_silence_ms,
                                     config.no_speech_timeout_s, config.max_utterance_s)
        self.stt = Transcriber(config.whisper_model, config.whisper_compute, config.language)
        self.speaker = Speaker(config.voice, config.speech_rate)
        self.memory = Memory_path(config)
        self.brain = ClaudeBrain(config, self.memory)
        self.mac_skills = OfflineSkills(config, self.memory, self.brain.mac)
        self._state = IDLE
        self._trigger = threading.Event()   # set by tap/hotkey to force listening
        self._running = False

    # ------------------------------------------------------------------
    def _set_state(self, state: str) -> None:
        self._state = state
        bus.publish({"type": "state", "value": state})

    def trigger(self) -> None:
        """External push-to-talk (orb tap or hotkey). Also barges in."""
        if self._state == SPEAKING:
            self.speaker.interrupt()
        self._trigger.set()

    # ------------------------------------------------------------------
    def start(self) -> None:
        self._running = True
        self.capture.start()
        threading.Thread(target=self.stt.warm_up, daemon=True).start()
        threading.Thread(target=self._level_pump, daemon=True).start()
        self._set_state(IDLE)
        if self.wake and self.wake.available:
            bus.publish({"type": "caption", "value": "Say “Hey Jarvis”"})
        else:
            bus.publish({"type": "caption", "value": "Tap to talk"})
        self._loop()

    def stop(self) -> None:
        self._running = False
        self.capture.stop()

    def _level_pump(self) -> None:
        while self._running:
            bus.publish({"type": "level", "value": round(self.capture.level, 3)})
            time.sleep(0.05)

    # ------------------------------------------------------------------
    def _loop(self) -> None:
        while self._running:
            if self._await_trigger():
                self._converse()

    def _await_trigger(self) -> bool:
        """Block in idle until wake word, tap, or hotkey. Returns True to listen."""
        if self.wake:
            self.wake.reset()
        while self._running:
            if self._trigger.is_set():
                self._trigger.clear()
                return True
            chunk = self.capture.read(timeout=0.5)
            if chunk is None:
                continue
            if self.wake and self.wake.feed(chunk):
                return True
        return False

    def _listen(self) -> np.ndarray:
        """Record one utterance, starting from the pre-roll. Returns audio."""
        self._set_state(LISTENING)
        chime.play("wake", self.config.chime)
        bus.publish({"type": "caption", "value": "Listening…"})
        self.endpointer.reset(preroll=self.capture.preroll())
        # Drain stale chunks so we don't process pre-trigger audio twice.
        while True:
            status = Endpointer.ACTIVE
            chunk = self.capture.read(timeout=1.0)
            if chunk is None:
                if not self._running:
                    return np.zeros(0, dtype=np.int16)
                continue
            status = self.endpointer.feed(chunk)
            if status == Endpointer.DONE:
                break
            if status == Endpointer.TIMEOUT:
                return np.zeros(0, dtype=np.int16)
        return self.endpointer.audio()

    def _converse(self) -> None:
        follow_up = False
        while self._running:
            audio = self._listen()
            if audio.size == 0:
                if not follow_up:
                    chime.play("cancel", self.config.chime)
                    bus.publish({"type": "caption", "value": ""})
                self._set_state(IDLE)
                return

            self._set_state(THINKING)
            chime.play("accept", self.config.chime)
            bus.publish({"type": "caption", "value": "…"})
            text = self.stt.transcribe(audio).strip()
            if not text:
                self._set_state(IDLE)
                bus.publish({"type": "caption", "value": ""})
                return

            bus.publish({"type": "caption", "value": text})
            self.memory.add_turn("user", text)

            reply = self._respond(text)
            self.memory.add_turn("assistant", reply)

            # Follow-up window: keep the conversation open without the wake word.
            if self.config.follow_up_s > 0 and reply:
                follow_up = self._wait_for_follow_up()
                if follow_up:
                    continue
            self._set_state(IDLE)
            bus.publish({"type": "caption", "value": ""})
            return

    def _respond(self, text: str) -> str:
        # 1) Instant offline skills (time, math, timers, volume, apps, memory).
        local = self.mac_skills.handle(text)
        if local is not None:
            if local == "":  # "stop"/"never mind" — acknowledged silently
                return ""
            self._set_state(SPEAKING)
            bus.publish({"type": "caption", "value": local})
            self.speaker.say(local)
            self.speaker.wait_until_done(timeout=30)
            return local

        # 2) Claude — streamed, spoken sentence by sentence.
        self._set_state(SPEAKING)
        streamer = SentenceStreamer(self.speaker)
        caption = {"text": ""}
        interrupted = threading.Event()

        # A watcher lets the wake word / tap barge in during the reply.
        watcher = threading.Thread(target=self._barge_in_watch, args=(interrupted,),
                                   daemon=True)
        watcher.start()

        def on_delta(delta: str) -> None:
            caption["text"] += delta
            streamer.feed(delta)
            bus.publish({"type": "caption", "value": caption["text"][-240:]})

        reply = self.brain.answer(text, on_delta, should_stop=interrupted.is_set)
        streamer.flush()
        if not interrupted.is_set():
            self.speaker.wait_until_done(timeout=90)
        interrupted.set()  # stop the watcher
        return reply

    def _barge_in_watch(self, interrupted: threading.Event) -> None:
        """While speaking, listen for the wake word or a tap to cut Jarvis off."""
        if self.wake:
            self.wake.reset()
        while not interrupted.is_set() and self._running:
            if self._trigger.is_set():
                self._trigger.clear()
                self.speaker.interrupt()
                interrupted.set()
                # Re-arm so _converse's next _listen picks up immediately.
                self._trigger.set()
                return
            chunk = self.capture.read(timeout=0.2)
            if chunk is None:
                continue
            if self.wake and self.wake.feed(chunk):
                self.speaker.interrupt()
                interrupted.set()
                self._trigger.set()
                return

    def _wait_for_follow_up(self) -> bool:
        """After a reply, listen briefly for continued speech (no wake word).

        Returns True as soon as the user starts talking; the outer loop's next
        `_listen()` re-captures the utterance (its pre-roll buffer already holds
        the opening words, so nothing is lost)."""
        bus.publish({"type": "caption", "value": ""})
        self._set_state(LISTENING)
        probe = Endpointer(self.config.sample_rate, self.config.vad_aggressiveness)
        probe.reset()
        deadline = time.monotonic() + self.config.follow_up_s
        while time.monotonic() < deadline and self._running:
            if self._trigger.is_set():
                self._trigger.clear()
                return True
            chunk = self.capture.read(timeout=0.3)
            if chunk is None:
                continue
            probe.feed(chunk)
            if probe.heard_speech:
                return True
        return False


def Memory_path(config):
    from .config import DB_PATH
    return Memory(DB_PATH)
