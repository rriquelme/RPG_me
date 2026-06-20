"""Persistence layer.

A tiny repository interface with a local JSON implementation. When you move to
the cloud, add a ``DynamoStore(Store)`` with the same methods and the rest of
the engine stays unchanged.

State shape (JSON):
{
  "user": "ramon",
  "skills": {"health": {"axis_key": "health", "total_exp": 120}, ...},
  "events": [
    {"id": "...", "axis_key": "health", "name": "gym",
     "exp": 10, "timestamp": "2026-06-20T21:05:00", "note": ""}
  ]
}
"""

from __future__ import annotations

import abc
import json
import os
from typing import Any, Dict, List


class Store(abc.ABC):
    """Abstract storage so the engine doesn't care where data lives."""

    @abc.abstractmethod
    def load(self) -> Dict[str, Any]: ...

    @abc.abstractmethod
    def save(self, state: Dict[str, Any]) -> None: ...


def empty_state(user: str = "me") -> Dict[str, Any]:
    return {"user": user, "skills": {}, "events": []}


class JSONStore(Store):
    """Reads/writes the whole state to a single JSON file."""

    def __init__(self, path: str = "data/save_file.json", user: str = "me") -> None:
        self.path = path
        self.user = user

    def load(self) -> Dict[str, Any]:
        if os.path.isfile(self.path):
            with open(self.path, "r", encoding="utf-8") as fh:
                state = json.load(fh)
            state.setdefault("user", self.user)
            state.setdefault("skills", {})
            state.setdefault("events", [])
            return state
        return empty_state(self.user)

    def save(self, state: Dict[str, Any]) -> None:
        os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
        with open(self.path, "w", encoding="utf-8") as fh:
            json.dump(state, fh, indent=2, ensure_ascii=False)


class MemoryStore(Store):
    """In-memory store, handy for tests."""

    def __init__(self, user: str = "me") -> None:
        self._state: Dict[str, Any] = empty_state(user)

    def load(self) -> Dict[str, Any]:
        return self._state

    def save(self, state: Dict[str, Any]) -> None:
        self._state = state
