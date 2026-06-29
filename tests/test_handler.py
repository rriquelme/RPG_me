"""Tests for the Lambda router — no AWS required (engine uses MemoryStore)."""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))

from rpgme.engine import Engine  # noqa: E402
from rpgme.store import MemoryStore  # noqa: E402

import handler  # noqa: E402

# One shared in-memory store per user so state + config persist across requests;
# the engine is rebuilt per call from the store's config (mirrors production).
_stores: dict = {}


def _factory(user: str) -> Engine:
    store = _stores.setdefault(user, MemoryStore(user))
    return handler.engine_for(store)


def _event(route, body=None, path_params=None, qs=None):
    return {
        "routeKey": route,
        "body": json.dumps(body) if body is not None else None,
        "pathParameters": path_params or {},
        "queryStringParameters": qs or {},
    }


def setup_function(_fn):
    _stores.clear()


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


def test_sync_is_idempotent():
    batch = {
        "events": [
            {"id": "a1", "axis": "mind", "name": "study", "exp": 45, "seconds": 2700},
            {"id": "a2", "axis": "health", "name": "gym", "exp": 10, "seconds": 0},
        ]
    }
    r1 = handler.handle(_event("POST /sync", body=batch), engine_factory=_factory)
    assert r1["statusCode"] == 200
    assert sorted(json.loads(r1["body"])["applied"]) == ["a1", "a2"]

    # Re-sync the same batch: all duplicates, totals unchanged.
    r2 = handler.handle(_event("POST /sync", body=batch), engine_factory=_factory)
    b2 = json.loads(r2["body"])
    assert b2["applied"] == []
    assert sorted(b2["duplicates"]) == ["a1", "a2"]
    assert b2["total_events"] == 2

    res = handler.handle(_event("GET /summary"), engine_factory=_factory)
    assert json.loads(res["body"])["total_events"] == 2  # not 4


def test_log_with_client_id_is_idempotent():
    body = {"id": "x9", "axis": "mind", "name": "read"}
    r1 = handler.handle(_event("POST /log", body=body), engine_factory=_factory)
    assert r1["statusCode"] == 201
    r2 = handler.handle(_event("POST /log", body=body), engine_factory=_factory)
    assert r2["statusCode"] == 200
    assert json.loads(r2["body"])["status"] == "duplicate"


def _axes(n):
    return [
        {"key": f"a{i}", "label": f"Axis {i}", "description": "", "color": "#4C72B0"}
        for i in range(n)
    ]


def test_put_config_sets_axes_and_get_reflects_it():
    res = handler.handle(
        _event("PUT /config", body={"axes": _axes(6)}), engine_factory=_factory
    )
    assert res["statusCode"] == 200
    assert json.loads(res["body"])["count"] == 6

    res = handler.handle(_event("GET /config"), engine_factory=_factory)
    keys = [a["key"] for a in json.loads(res["body"])["axes"]]
    assert keys == [f"a{i}" for i in range(6)]


def test_config_rejects_out_of_range_counts():
    for n in (2, 11):
        res = handler.handle(
            _event("PUT /config", body={"axes": _axes(n)}), engine_factory=_factory
        )
        assert res["statusCode"] == 400


def test_config_accepts_minimum_three_axes():
    res = handler.handle(
        _event("PUT /config", body={"axes": _axes(3)}), engine_factory=_factory
    )
    assert res["statusCode"] == 200
    assert json.loads(res["body"])["count"] == 3


def test_sync_accepts_events_for_custom_axes_after_config():
    # Configure custom axes, then sync an event referencing one of them.
    handler.handle(_event("PUT /config", body={"axes": _axes(7)}), engine_factory=_factory)
    res = handler.handle(
        _event("POST /sync", body={"events": [
            {"id": "e1", "axis": "a3", "name": "study", "exp": 20, "seconds": 1200},
        ]}),
        engine_factory=_factory,
    )
    assert res["statusCode"] == 200
    assert json.loads(res["body"])["applied"] == ["e1"]

    res = handler.handle(_event("GET /summary"), engine_factory=_factory)
    oct_keys = {a["key"] for a in json.loads(res["body"])["octagon"]}
    assert "a3" in oct_keys  # custom axis is part of the octagon


def test_log_timed_session_and_time_route():
    res = handler.handle(
        _event("POST /log", body={"axis": "mind", "name": "study", "seconds": 1800}),
        engine_factory=_factory,
    )
    assert res["statusCode"] == 201
    assert json.loads(res["body"])["event"]["seconds"] == 1800

    res = handler.handle(_event("GET /time"), engine_factory=_factory)
    periods = json.loads(res["body"])["periods"]
    assert periods["today"]["by_activity"]["study"] == 1800
    assert periods["ytd"]["total_seconds"] == 1800
