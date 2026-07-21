"""Offline skills — instant answers that never need the network or Claude.

These handle the everyday commands a good assistant should answer in
milliseconds even with the Wi-Fi off: time, date, timers, simple math, volume,
launching apps, and remembering facts. The orchestrator tries these first; only
if none match does the request go to Claude.

Each handler returns a spoken string, or None if it doesn't handle the input.
"""

from __future__ import annotations

import ast
import datetime as _dt
import operator
import re
import subprocess
import threading
import time

from ..audio import chime as _chime


# ---- safe arithmetic -------------------------------------------------
_OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
        ast.Div: operator.truediv, ast.Pow: operator.pow, ast.Mod: operator.mod,
        ast.USub: operator.neg, ast.FloorDiv: operator.floordiv}


def _safe_eval(node):
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.BinOp):
        return _OPS[type(node.op)](_safe_eval(node.left), _safe_eval(node.right))
    if isinstance(node, ast.UnaryOp):
        return _OPS[type(node.op)](_safe_eval(node.operand))
    raise ValueError("unsupported")


_WORDS = {"plus": "+", "minus": "-", "times": "*", "multiplied by": "*",
          "divided by": "/", "over": "/", "x": "*", "power": "**", "mod": "%",
          "squared": "**2", "cubed": "**3"}


class OfflineSkills:
    def __init__(self, config, memory, mac_tools) -> None:
        self.config = config
        self.memory = memory
        self.mac = mac_tools
        self._timers: list[threading.Timer] = []

    def handle(self, text: str) -> str | None:
        t = text.lower().strip().rstrip("?.!")
        if not t:
            return None
        for fn in (self._time, self._date, self._timer, self._math,
                   self._volume, self._open, self._remember, self._recall,
                   self._greeting):
            try:
                out = fn(t, text)
            except Exception:
                out = None
            if out is not None:
                return out
        return None

    # ------------------------------------------------------------------
    def _time(self, t, _raw):
        if re.search(r"\b(what.?s the |current |the )?time\b", t) and "timer" not in t:
            return "It's " + _dt.datetime.now().strftime("%-I:%M %p") + "."
        return None

    def _date(self, t, _raw):
        if re.search(r"\b(what.?s |today.?s |the )?(date|day)\b", t) and "birthday" not in t:
            return "Today is " + _dt.datetime.now().strftime("%A, %B %-d, %Y") + "."
        return None

    def _timer(self, t, _raw):
        m = re.search(r"(?:set (?:a )?timer|remind me) (?:for |in )?(\d+)\s*"
                      r"(second|minute|hour)s?", t)
        if not m:
            return None
        n = int(m.group(1))
        unit = m.group(2)
        secs = n * {"second": 1, "minute": 60, "hour": 3600}[unit]

        def _fire():
            _chime.play("wake", self.config.chime)
            subprocess.run(["osascript", "-e",
                            f'display notification "Timer done" with title "Jarvis" sound name "Glass"'])

        timer = threading.Timer(secs, _fire)
        timer.daemon = True
        timer.start()
        self._timers.append(timer)
        return f"Timer set for {n} {unit}{'s' if n != 1 else ''}."

    def _math(self, t, _raw):
        if not re.search(r"\d", t):
            return None
        expr = t
        for w, sym in _WORDS.items():
            expr = expr.replace(w, sym)
        expr = re.sub(r"(what|whats|what's|is|calculate|compute|equals?|the|of|"
                      r"result)", " ", expr)
        expr = expr.replace("%", " % ")
        expr = re.sub(r"[^0-9+\-*/%.()\s]", "", expr).strip()
        if not expr or not re.search(r"[-+*/%]", expr):
            return None
        try:
            val = _safe_eval(ast.parse(expr, mode="eval").body)
        except Exception:
            return None
        if isinstance(val, float) and val.is_integer():
            val = int(val)
        elif isinstance(val, float):
            val = round(val, 6)
        return f"That's {val}."

    def _volume(self, t, _raw):
        if "volume" not in t and "mute" not in t and "unmute" not in t:
            return None
        if "mute" in t and "un" not in t:
            return self.mac.run("set_volume", {"mute": True})
        if "unmute" in t:
            return self.mac.run("set_volume", {"mute": False})
        m = re.search(r"(\d+)", t)
        if m:
            return self.mac.run("set_volume", {"level": int(m.group(1))})
        if "up" in t or "louder" in t:
            return self.mac.run("set_volume", {"level": 80})
        if "down" in t or "quieter" in t or "lower" in t:
            return self.mac.run("set_volume", {"level": 30})
        return None

    def _open(self, t, _raw):
        m = re.match(r"(?:open|launch|start|switch to) (?:the )?(.+?)(?: app)?$", t)
        if not m:
            return None
        target = m.group(1).strip()
        if not target or target in {"up", "it", "that", "the door", "the window"}:
            return None
        return self.mac.run("open_app", {"name": target.title()})

    def _remember(self, t, raw):
        m = re.match(r"(?:remember|note) that (.+?) (?:is|are|=|equals) (.+)", t)
        if not m:
            m2 = re.match(r"my (.+?) is (.+)", t)
            if m2:
                self.memory.set_fact(m2.group(1), m2.group(2))
                return f"Got it — your {m2.group(1)} is {m2.group(2)}."
            return None
        self.memory.set_fact(m.group(1), m.group(2))
        return "I'll remember that."

    def _recall(self, t, _raw):
        m = re.match(r"what(?:'s| is) my (.+)", t)
        if not m:
            return None
        facts = self.memory.all_facts()
        key = m.group(1).strip()
        if key in facts:
            return f"Your {key} is {facts[key]}."
        return None

    def _greeting(self, t, _raw):
        if t in {"hi", "hello", "hey", "yo", "hey jarvis", "jarvis"}:
            return "Hey — I'm listening."
        if "thank" in t:
            return "Anytime."
        if t in {"stop", "cancel", "never mind", "nevermind", "quiet", "shut up"}:
            return ""  # handled as a barge-in; empty = acknowledged silently
        return None
