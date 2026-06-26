"""AWS Lambda handler for the RPG_me HTTP API.

A single function with a tiny router (cheap, simple, one cold-start path). The
business logic lives entirely in the storage-agnostic ``rpgme.Engine``; this
file only translates HTTP <-> engine calls.

Routes (API Gateway HTTP API, payload v2):
    GET  /axes                  list the configured octagon axes
    POST /log                   {axis, name, exp?, note?, seconds?, id?} -> log
                                a routine; seconds>0 records a timed session
    POST /sync                  {events:[...]} -> idempotently apply offline
                                events (by client id)
    GET  /summary               levels + counts snapshot (dashboard payload)
    GET  /time                  tracked time by activity/axis per period
    GET  /octagon               just the radar-chart data
    GET  /streak/{name}         current daily streak for an activity

User identity comes from the ``?user=`` query param for now; swap in a Cognito
authorizer / JWT claim before exposing this publicly (see backend/README.md).
"""

from __future__ import annotations

import base64
import json
import os
from typing import Any, Callable, Dict

from rpgme.config import load_axes
from rpgme.engine import Engine
from rpgme.store import DynamoStore

TABLE_NAME = os.environ.get("TABLE_NAME", "rpg_me")
DEFAULT_USER = os.environ.get("DEFAULT_USER", "me")


def make_engine(user: str) -> Engine:
    return Engine(DynamoStore(table_name=TABLE_NAME, user=user))


def _resp(status: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def _body(event: Dict[str, Any]) -> Dict[str, Any]:
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    return json.loads(raw)


def _route_key(event: Dict[str, Any]) -> str:
    # HTTP API v2 provides "routeKey"; fall back for REST/v1 events.
    if event.get("routeKey"):
        return event["routeKey"]
    ctx = event.get("requestContext", {}).get("http", {})
    method = ctx.get("method") or event.get("httpMethod", "GET")
    path = ctx.get("path") or event.get("path", "/")
    return f"{method} {path}"


def handle(event: Dict[str, Any], engine_factory: Callable[[str], Engine] = make_engine) -> Dict[str, Any]:
    """Pure router — injectable engine factory makes it testable without AWS."""
    route = _route_key(event)
    qs = event.get("queryStringParameters") or {}
    user = qs.get("user") or DEFAULT_USER
    path_params = event.get("pathParameters") or {}

    try:
        if route == "GET /axes":
            return _resp(200, {"axes": [a.to_dict() for a in load_axes()]})

        eng = engine_factory(user)

        if route == "POST /log":
            body = _body(event)
            event_id = body.get("id")
            if event_id and eng.has_event(event_id):
                # Idempotent: a retried offline event is already recorded.
                return _resp(200, {"status": "duplicate", "id": event_id})
            seconds = int(body.get("seconds", 0))
            if seconds > 0:
                # Timed session: exp defaults to one point per tracked minute.
                exp = body.get("exp")
                ev = eng.log_time(
                    body["axis"],
                    body["name"],
                    seconds,
                    exp=int(exp) if exp is not None else None,
                    note=body.get("note", ""),
                    event_id=event_id,
                )
            else:
                ev = eng.log(
                    body["axis"],
                    body["name"],
                    exp=int(body.get("exp", 10)),
                    note=body.get("note", ""),
                    event_id=event_id,
                )
            eng.save()
            return _resp(201, {"event": ev, "skill": eng.skill(ev["axis_key"]).to_dict()})

        if route == "GET /summary":
            return _resp(200, eng.summary())

        if route == "POST /sync":
            body = _body(event)
            events = body.get("events", [])
            if not isinstance(events, list):
                return _resp(400, {"error": "'events' must be a list"})
            result = eng.apply_events(events)
            eng.save()
            return _resp(200, {**result, "total_events": len(eng.state["events"])})

        if route == "GET /time":
            return _resp(200, {"periods": eng.time_periods()})

        if route == "GET /octagon":
            return _resp(200, {"octagon": eng.octagon()})

        if route.startswith("GET /streak"):
            name = path_params.get("name") or qs.get("name")
            if not name:
                return _resp(400, {"error": "missing activity name"})
            return _resp(200, {"name": name, "streak": eng.streak(name)})

        return _resp(404, {"error": "not found", "route": route})

    except KeyError as exc:
        return _resp(400, {"error": f"missing field: {exc}"})
    except ValueError as exc:
        return _resp(400, {"error": str(exc)})


def lambda_handler(event: Dict[str, Any], context: Any = None) -> Dict[str, Any]:
    return handle(event)
