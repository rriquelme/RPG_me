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


class DynamoStore(Store):
    """Single-table DynamoDB implementation of the same Store interface.

    Layout (one table, partitioned per user):

        PK = "USER#<user>"
        SK = "PROFILE"                       -> {user}
        SK = "SKILL#<axis_key>"              -> {axis_key, total_exp}
        SK = "EVENT#<timestamp>#<id>"        -> the full event

    ``save()`` is incremental: skills (8 small items) and the profile are
    rewritten, but only *new* events are written — ``load()`` remembers which
    event ids already exist, so re-saving doesn't rewrite history. That keeps
    the Store interface identical to JSONStore while staying cheap at scale.

    boto3 is imported lazily so importing rpgme never requires AWS deps.
    """

    def __init__(self, table_name: str, user: str = "me", region: str = None) -> None:
        import boto3  # lazy: only needed when actually talking to AWS

        self.user = user
        self.table_name = table_name
        kwargs = {"region_name": region} if region else {}
        self._table = boto3.resource("dynamodb", **kwargs).Table(table_name)
        self._known_event_ids: set = set()

    @property
    def _pk(self) -> str:
        return f"USER#{self.user}"

    @staticmethod
    def _to_int(value: Any) -> int:
        # DynamoDB returns numbers as Decimal.
        return int(value) if value is not None else 0

    def load(self) -> Dict[str, Any]:
        from boto3.dynamodb.conditions import Key

        skills: Dict[str, Any] = {}
        events: List[Dict[str, Any]] = []
        user = self.user

        kwargs = {"KeyConditionExpression": Key("PK").eq(self._pk)}
        while True:
            resp = self._table.query(**kwargs)
            for item in resp.get("Items", []):
                sk = item.get("SK", "")
                if sk == "PROFILE":
                    user = item.get("user", user)
                elif sk.startswith("SKILL#"):
                    skills[item["axis_key"]] = {
                        "axis_key": item["axis_key"],
                        "total_exp": self._to_int(item.get("total_exp")),
                    }
                elif sk.startswith("EVENT#"):
                    events.append(
                        {
                            "id": item["id"],
                            "axis_key": item["axis_key"],
                            "name": item["name"],
                            "exp": self._to_int(item.get("exp")),
                            "note": item.get("note", ""),
                            "timestamp": item["timestamp"],
                        }
                    )
            if "LastEvaluatedKey" in resp:
                kwargs["ExclusiveStartKey"] = resp["LastEvaluatedKey"]
            else:
                break

        events.sort(key=lambda e: e["timestamp"])
        self._known_event_ids = {e["id"] for e in events}
        return {"user": user, "skills": skills, "events": events}

    def save(self, state: Dict[str, Any]) -> None:
        with self._table.batch_writer() as batch:
            batch.put_item(Item={"PK": self._pk, "SK": "PROFILE", "user": state.get("user", self.user)})

            for axis_key, skill in state.get("skills", {}).items():
                batch.put_item(
                    Item={
                        "PK": self._pk,
                        "SK": f"SKILL#{axis_key}",
                        "axis_key": axis_key,
                        "total_exp": int(skill["total_exp"]),
                    }
                )

            for ev in state.get("events", []):
                if ev["id"] in self._known_event_ids:
                    continue
                batch.put_item(
                    Item={
                        "PK": self._pk,
                        "SK": f"EVENT#{ev['timestamp']}#{ev['id']}",
                        "id": ev["id"],
                        "axis_key": ev["axis_key"],
                        "name": ev["name"],
                        "exp": int(ev["exp"]),
                        "note": ev.get("note", ""),
                        "timestamp": ev["timestamp"],
                    }
                )
                self._known_event_ids.add(ev["id"])
