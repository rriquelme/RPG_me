"""Tests for the Lambda router — no AWS required (engine uses MemoryStore)."""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))

from rpgme.engine import Engine  # noqa: E402
from rpgme.store import MemoryStore  # noqa: E402

import handler  # noqa: E402

# One shared in-memory engine per user so state persists across requests.
_engines: dict = {}


def _factory(user: str) -> Engine:
    if user not in _engines:
        _engines[user] = Engine(MemoryStore(user))
    return _engines[user]


def _event(route, body=None, path_params=None, qs=None):
    return {
        "routeKey": route,
        "body": json.dumps(body) if body is not None else None,
        "pathParameters": path_params or {},
        "queryStringParameters": qs or {},
    }


def setup_function(_fn):
    _engines.clear()


def test_axes_route():
    res = handler.handle(_event("GET /axes"), engine_factory=_factory)
    assert res["statusCode"] == 200
    assert len(json.loads(res["body"])["axes"]) == 8


def test_log_then_summary():
    res = handler.handle(
        _event("POST /log", body={"axis": "health", "name": "gym", "exp": 75}),
        engine_factory=_factory,
    )
    assert res["statusCode"] == 201
    assert json.loads(res["body"])["skill"]["level"] == 2

    res = handler.handle(_event("GET /summary"), engine_factory=_factory)
    body = json.loads(res["body"])
    assert body["total_events"] == 1
    assert body["counts_all_time"]["gym"] == 1


def test_log_unknown_axis_is_400():
    res = handler.handle(
        _event("POST /log", body={"axis": "nope", "name": "x"}),
        engine_factory=_factory,
    )
    assert res["statusCode"] == 400


def test_streak_route():
    handler.handle(
        _event("POST /log", body={"axis": "mind", "name": "read"}),
        engine_factory=_factory,
    )
    res = handler.handle(
        _event("GET /streak/{name}", path_params={"name": "read"}),
        engine_factory=_factory,
    )
    assert json.loads(res["body"])["streak"] == 1


def test_unknown_route_404():
    res = handler.handle(_event("GET /nope"), engine_factory=_factory)
    assert res["statusCode"] == 404
