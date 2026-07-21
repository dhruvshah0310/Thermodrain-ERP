"""Configuration for Jarvis.

Settings live in ~/.jarvis/config.json and can be overridden by environment
variables (ANTHROPIC_API_KEY in particular). Every field has a sane default so
Jarvis runs out of the box after `install.sh`.
"""

from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field
from pathlib import Path

JARVIS_HOME = Path(os.environ.get("JARVIS_HOME", Path.home() / ".jarvis"))
CONFIG_PATH = JARVIS_HOME / "config.json"
DB_PATH = JARVIS_HOME / "jarvis.db"
LOG_PATH = JARVIS_HOME / "jarvis.log"


@dataclass
class Config:
    # --- Claude / brain ---
    model: str = "claude-opus-4-8"
    max_tokens: int = 2048
    effort: str = "low"                 # low|medium|high — low keeps voice replies snappy
    web_search: bool = True             # let Claude search the internet server-side
    max_web_searches: int = 3
    history_turns: int = 6              # conversational turns kept as context

    # --- audio ---
    sample_rate: int = 16000
    chunk_ms: int = 80                  # 80ms chunks — what openWakeWord expects
    input_device: int | None = None     # None = system default microphone
    preroll_ms: int = 600               # audio kept from *before* speech starts

    # --- wake word ---
    wake_word_enabled: bool = True
    wake_threshold: float = 0.5
    wake_refractory_s: float = 2.0

    # --- endpointing (when to stop listening) ---
    vad_aggressiveness: int = 2         # 0..3, higher = stricter about what counts as speech
    trailing_silence_ms: int = 800      # stop this long after you stop talking
    no_speech_timeout_s: float = 7.0    # give up if you never start talking
    max_utterance_s: float = 20.0

    # --- speech to text ---
    whisper_model: str = "base.en"      # tiny.en | base.en | small.en | medium.en
    whisper_compute: str = "int8"
    language: str = "en"

    # --- text to speech ---
    voice: str = ""                     # "" = system default; try "Zoe (Premium)" or "Tom"
    speech_rate: int = 190              # words per minute

    # --- interaction ---
    follow_up_s: float = 6.0            # keep listening after a reply, no wake word needed (0 = off)
    chime: bool = True
    hotkey: str = "<alt>+<space>"       # push-to-talk toggle, works even with wake word off

    # --- mac control ---
    allow_shell: bool = True            # let Claude run shell commands via the run_shell tool
    shell_timeout_s: int = 30

    # --- offline learning ---
    cache_answers: bool = True
    cache_similarity: float = 0.86      # how close a question must be to reuse a cached answer
    offline_only_cache: bool = True     # True: cache used only when offline; False: cache-first always

    # --- UI ---
    ui_port: int = 8971
    show_ui: bool = True

    api_key: str = field(default="", repr=False)

    def resolved_api_key(self) -> str:
        return os.environ.get("ANTHROPIC_API_KEY") or self.api_key

    @classmethod
    def load(cls) -> "Config":
        JARVIS_HOME.mkdir(parents=True, exist_ok=True)
        cfg = cls()
        if CONFIG_PATH.exists():
            try:
                data = json.loads(CONFIG_PATH.read_text())
                for k, v in data.items():
                    if hasattr(cfg, k):
                        setattr(cfg, k, v)
            except Exception:
                pass  # corrupt config: fall back to defaults rather than crash
        return cfg

    def save(self) -> None:
        JARVIS_HOME.mkdir(parents=True, exist_ok=True)
        CONFIG_PATH.write_text(json.dumps(asdict(self), indent=2))
