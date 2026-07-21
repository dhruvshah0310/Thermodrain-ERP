"""The Claude-powered brain.

Streams a spoken reply from Claude Opus 4.8, with:

- Server-side **web search** so internet questions get complete, current
  answers ("give me complete answers using the Claude platform for all
  internet-related things").
- **Mac-control tools** so Claude can actually operate the laptop.
- **Streaming**, so the first sentence is spoken while the rest is still being
  generated — the assistant feels instant.
- **Offline learning**: the final answer to a factual question is cached, so
  the same question can be answered later without the network.

Model/thinking/effort follow the Claude API guidance for Opus 4.8: adaptive
thinking is available but we keep `effort: low` by default for snappy voice
latency, and stream because voice replies can run long.
"""

from __future__ import annotations

import socket
from typing import Callable

from .mac_tools import MacTools, tool_specs

WEB_SEARCH_TOOL = {"type": "web_search_20260209", "name": "web_search"}

SYSTEM_PROMPT = """You are Jarvis, a friendly, sharp voice assistant living on the user's Mac.

You are being spoken to out loud and your replies are read aloud by text-to-speech, so:
- Be concise and conversational. Usually 1-3 sentences. No markdown, no bullet
  lists, no emoji, no code blocks — just natural spoken language.
- Lead with the answer. Skip preamble like "Sure!" or "Great question".
- Spell things for the ear: say "10 a.m.", "72 degrees", "about 3 and a half".

You can control the Mac with the provided tools (open apps, set volume, control
media, run shell commands, etc.). When the user asks you to *do* something on the
computer, use the tools rather than describing the steps. Confirm briefly once done.

For anything about the wider world — news, facts, current events, prices,
weather, how-to — use web search to give a complete, accurate, up-to-date answer.

Never mention that you are an AI model or which model you are unless asked."""


def _online() -> bool:
    try:
        socket.setdefaulttimeout(1.5)
        socket.socket(socket.AF_INET, socket.SOCK_STREAM).connect(("1.1.1.1", 53))
        return True
    except Exception:
        return False


class ClaudeBrain:
    def __init__(self, config, memory) -> None:
        self.config = config
        self.memory = memory
        self.mac = MacTools(config.allow_shell, config.shell_timeout_s)
        self._client = None

    def _ensure_client(self):
        if self._client is None:
            from anthropic import Anthropic
            key = self.config.resolved_api_key()
            self._client = Anthropic(api_key=key) if key else Anthropic()
        return self._client

    @staticmethod
    def online() -> bool:
        return _online()

    # ------------------------------------------------------------------
    def answer(self, user_text: str, on_delta: Callable[[str], None],
               should_stop: Callable[[], bool]) -> str:
        """Stream an answer. Calls on_delta(text) as words arrive; returns the
        full text. Falls back to the offline cache when there's no network."""

        # Offline (or cache-first): try the learned knowledge cache.
        cache_first = self.config.cache_answers and not self.config.offline_only_cache
        offline = not _online()
        if (offline or cache_first) and self.config.cache_answers:
            hit = self.memory.lookup(user_text, self.config.cache_similarity)
            if hit is not None:
                answer, _score = hit
                on_delta(answer)
                return answer
        if offline:
            msg = ("I can't reach the internet right now, and I don't have that "
                   "one saved yet. Ask me again when you're back online.")
            on_delta(msg)
            return msg

        return self._stream_from_claude(user_text, on_delta, should_stop)

    # ------------------------------------------------------------------
    def _build_messages(self, user_text: str) -> list[dict]:
        messages = self.memory.recent_turns(self.config.history_turns)
        facts = self.memory.all_facts()
        preface = ""
        if facts:
            known = "; ".join(f"{k}: {v}" for k, v in facts.items())
            preface = f"(Things you know about the user: {known}.)\n\n"
        messages.append({"role": "user", "content": preface + user_text})
        return messages

    def _tools(self) -> list[dict]:
        tools = list(tool_specs(self.config.allow_shell))
        if self.config.web_search:
            tools.append({**WEB_SEARCH_TOOL, "max_uses": self.config.max_web_searches})
        return tools

    def _stream_from_claude(self, user_text, on_delta, should_stop) -> str:
        client = self._ensure_client()
        messages = self._build_messages(user_text)
        tools = self._tools()
        full_text = ""
        used_web = False

        # Agentic loop: keep going while Claude calls (client-side) tools.
        for _turn in range(6):
            if should_stop():
                break
            spoken_this_turn = ""
            try:
                with client.messages.stream(
                    model=self.config.model,
                    max_tokens=self.config.max_tokens,
                    system=SYSTEM_PROMPT,
                    messages=messages,
                    tools=tools,
                    output_config={"effort": self.config.effort},
                ) as stream:
                    for event in stream:
                        if should_stop():
                            break
                        if event.type == "content_block_delta" and \
                                getattr(event.delta, "type", None) == "text_delta":
                            delta = event.delta.text
                            spoken_this_turn += delta
                            full_text += delta
                            on_delta(delta)
                    message = stream.get_final_message()
            except Exception as e:
                err = f"Sorry, I hit an error reaching Claude: {e}"
                on_delta(err)
                return err

            if should_stop():
                break

            if any(getattr(b, "type", "") == "server_tool_use" for b in message.content):
                used_web = True

            # Handle client-side tool calls (Mac control).
            tool_uses = [b for b in message.content if getattr(b, "type", "") == "tool_use"]
            if message.stop_reason == "pause_turn":
                messages.append({"role": "assistant", "content": message.content})
                continue
            if not tool_uses:
                break

            messages.append({"role": "assistant", "content": message.content})
            results = []
            for tu in tool_uses:
                result = self.mac.run(tu.name, tu.input or {})
                results.append({"type": "tool_result", "tool_use_id": tu.id,
                                "content": result})
            messages.append({"role": "user", "content": results})

        full_text = full_text.strip()
        # Learn from this exchange for offline use — but only cache factual,
        # web-answered questions, not "open safari" style commands.
        if self.config.cache_answers and used_web and full_text and len(full_text) < 800:
            self.memory.cache_answer(user_text, full_text)
        return full_text
