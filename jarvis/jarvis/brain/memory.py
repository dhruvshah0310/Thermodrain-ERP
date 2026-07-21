"""Persistent memory + offline knowledge cache.

Two jobs, both backed by one SQLite file in ~/.jarvis:

1. Conversation memory — recent turns, so Jarvis has context across a session
   and remembers facts you tell it ("my name is Dhruv") across restarts.

2. Offline knowledge cache — every answer Claude produces for a factual
   question is stored with its question. When the same (or a very similar)
   question comes back while you're offline, Jarvis answers from the cache
   instead of failing. This is the "learn from Claude so it works offline"
   behaviour: the more you use it online, the more it can answer offline.

Similarity uses a lightweight character-3-gram TF-IDF cosine — no heavy ML
dependency, works instantly, and is good enough to match paraphrases like
"what's the capital of france" vs "capital of france".
"""

from __future__ import annotations

import math
import re
import sqlite3
import threading
import time
from collections import Counter


def _ngrams(text: str, n: int = 3) -> Counter:
    text = re.sub(r"\s+", " ", text.lower().strip())
    text = re.sub(r"[^a-z0-9 ]", "", text)
    if len(text) < n:
        return Counter([text]) if text else Counter()
    return Counter(text[i:i + n] for i in range(len(text) - n + 1))


def _cosine(a: Counter, b: Counter) -> float:
    if not a or not b:
        return 0.0
    common = set(a) & set(b)
    dot = sum(a[k] * b[k] for k in common)
    na = math.sqrt(sum(v * v for v in a.values()))
    nb = math.sqrt(sum(v * v for v in b.values()))
    return dot / (na * nb) if na and nb else 0.0


class Memory:
    def __init__(self, db_path) -> None:
        self._db_path = str(db_path)
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(self._db_path, check_same_thread=False)
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._init_schema()

    def _init_schema(self) -> None:
        with self._conn:
            self._conn.execute("""
                CREATE TABLE IF NOT EXISTS turns (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ts REAL, role TEXT, content TEXT)""")
            self._conn.execute("""
                CREATE TABLE IF NOT EXISTS knowledge (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ts REAL, question TEXT, answer TEXT, hits INTEGER DEFAULT 0)""")
            self._conn.execute("""
                CREATE TABLE IF NOT EXISTS facts (
                    key TEXT PRIMARY KEY, value TEXT, ts REAL)""")

    # --- conversation history -----------------------------------------
    def add_turn(self, role: str, content: str) -> None:
        with self._lock, self._conn:
            self._conn.execute("INSERT INTO turns(ts, role, content) VALUES(?,?,?)",
                               (time.time(), role, content))

    def recent_turns(self, limit: int = 6) -> list[dict]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT role, content FROM turns ORDER BY id DESC LIMIT ?",
                (limit * 2,)).fetchall()
        turns = [{"role": r, "content": c} for r, c in reversed(rows)]
        # The API needs the first message to be from the user.
        while turns and turns[0]["role"] != "user":
            turns.pop(0)
        return turns

    # --- durable facts ("remember that ...") --------------------------
    def set_fact(self, key: str, value: str) -> None:
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT OR REPLACE INTO facts(key, value, ts) VALUES(?,?,?)",
                (key.lower().strip(), value.strip(), time.time()))

    def all_facts(self) -> dict[str, str]:
        with self._lock:
            rows = self._conn.execute("SELECT key, value FROM facts").fetchall()
        return {k: v for k, v in rows}

    # --- offline knowledge cache --------------------------------------
    def cache_answer(self, question: str, answer: str) -> None:
        q = question.strip()
        a = answer.strip()
        if len(q) < 3 or len(a) < 1:
            return
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT INTO knowledge(ts, question, answer, hits) VALUES(?,?,?,0)",
                (time.time(), q, a))

    def lookup(self, question: str, threshold: float = 0.86) -> tuple[str, float] | None:
        """Best cached answer for a similar question, if above threshold."""
        target = _ngrams(question)
        if not target:
            return None
        with self._lock:
            rows = self._conn.execute(
                "SELECT id, question, answer FROM knowledge").fetchall()
        best = None
        best_score = 0.0
        best_id = None
        for rid, q, a in rows:
            score = _cosine(target, _ngrams(q))
            if score > best_score:
                best_score, best, best_id = score, a, rid
        if best is not None and best_score >= threshold:
            with self._lock, self._conn:
                self._conn.execute(
                    "UPDATE knowledge SET hits = hits + 1 WHERE id = ?", (best_id,))
            return best, best_score
        return None
