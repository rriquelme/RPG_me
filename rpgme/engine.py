"""The engine: log events, level up skills, and compute counters.

This is the single entry point a UI (CLI today, Lambda/Flutter tomorrow) talks
to. It is storage-agnostic (takes a ``Store``) and config-driven (takes axes).
"""

from __future__ import annotations

import datetime as dt
import uuid
from collections import Counter, defaultdict
from typing import Any, Dict, List, Optional

from .config import load_axes
from .models import Axis, Skill


def _now_iso() -> str:
    return dt.datetime.now().replace(microsecond=0).isoformat()


def _parse(ts: str) -> dt.datetime:
    return dt.datetime.fromisoformat(ts)


class Engine:
    def __init__(self, store, axes: Optional[List[Axis]] = None) -> None:
        self.store = store
        self.axes: List[Axis] = axes if axes is not None else load_axes()
        self._axis_by_key = {a.key: a for a in self.axes}
        self.state: Dict[str, Any] = store.load()
        # Ensure a Skill exists for every configured axis.
        skills = self.state.setdefault("skills", {})
        for axis in self.axes:
            skills.setdefault(axis.key, {"axis_key": axis.key, "total_exp": 0})

    # --- persistence ------------------------------------------------------
    def save(self) -> None:
        self.store.save(self.state)

    # --- skills -----------------------------------------------------------
    def skill(self, axis_key: str) -> Skill:
        raw = self.state["skills"][axis_key]
        return Skill(axis_key=axis_key, total_exp=raw["total_exp"])

    def _persist_skill(self, skill: Skill) -> None:
        self.state["skills"][skill.axis_key] = {
            "axis_key": skill.axis_key,
            "total_exp": skill.total_exp,
        }

    # --- logging events ---------------------------------------------------
    def log(
        self,
        axis_key: str,
        name: str,
        exp: int = 10,
        note: str = "",
        timestamp: Optional[str] = None,
        seconds: int = 0,
    ) -> Dict[str, Any]:
        """Record one occurrence of a routine/activity and award exp.

        ``name`` is the thing you did (e.g. "gym", "read", "meditate"); it's
        what the counters/frequency stats are grouped by. ``seconds`` is the
        optional tracked duration of a timed session (0 for an instant tally).
        """
        if axis_key not in self._axis_by_key:
            raise ValueError(
                f"Unknown axis '{axis_key}'. Known: {list(self._axis_by_key)}"
            )
        event = {
            "id": uuid.uuid4().hex,
            "axis_key": axis_key,
            "name": name.strip().lower(),
            "exp": int(exp),
            "note": note,
            "timestamp": timestamp or _now_iso(),
            "seconds": int(seconds),
        }
        self.state["events"].append(event)

        skill = self.skill(axis_key)
        skill.gain_exp(exp)
        self._persist_skill(skill)
        return event

    def log_time(
        self,
        axis_key: str,
        name: str,
        seconds: int,
        exp: Optional[int] = None,
        note: str = "",
        timestamp: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Log a timed session. Exp defaults to one point per tracked minute."""
        seconds = max(0, int(seconds))
        if exp is None:
            exp = max(1, round(seconds / 60))
        return self.log(
            axis_key, name, exp=exp, note=note, timestamp=timestamp, seconds=seconds
        )

    # --- the octagon ------------------------------------------------------
    def octagon(self) -> List[Dict[str, Any]]:
        """The data behind the chart: one entry per axis, in config order."""
        out = []
        for axis in self.axes:
            skill = self.skill(axis.key)
            out.append(
                {
                    "key": axis.key,
                    "label": axis.label,
                    "color": axis.color,
                    "level": skill.level,
                    "total_exp": skill.total_exp,
                    "exp_into_level": skill.exp_into_level,
                    "exp_to_next": skill.exp_to_next,
                }
            )
        return out

    # --- counters / frequency --------------------------------------------
    def counts(self, since: Optional[dt.datetime] = None) -> Dict[str, int]:
        """Total occurrences per activity name (optionally within a window)."""
        c: Counter = Counter()
        for ev in self.state["events"]:
            if since and _parse(ev["timestamp"]) < since:
                continue
            c[ev["name"]] += 1
        return dict(c)

    def counts_last_days(self, days: int = 7) -> Dict[str, int]:
        since = dt.datetime.now() - dt.timedelta(days=days)
        return self.counts(since=since)

    def streak(self, name: str) -> int:
        """Current consecutive-day streak for an activity name."""
        name = name.strip().lower()
        days = {
            _parse(ev["timestamp"]).date()
            for ev in self.state["events"]
            if ev["name"] == name
        }
        if not days:
            return 0
        today = dt.date.today()
        # Allow the streak to be "alive" if done today or yesterday.
        start = today if today in days else today - dt.timedelta(days=1)
        if start not in days:
            return 0
        streak = 0
        cursor = start
        while cursor in days:
            streak += 1
            cursor -= dt.timedelta(days=1)
        return streak

    # --- time tracking ----------------------------------------------------
    @staticmethod
    def period_start(period: str, now: Optional[dt.datetime] = None) -> Optional[dt.datetime]:
        """Inclusive start datetime for a named period, or None for all-time.

        Periods: today, this_week (since Monday), this_month (since the 1st),
        ytd (since Jan 1), all_time.
        """
        now = now or dt.datetime.now()
        today = now.date()
        midnight = dt.time.min
        if period == "today":
            return dt.datetime.combine(today, midnight)
        if period == "this_week":
            monday = today - dt.timedelta(days=today.weekday())
            return dt.datetime.combine(monday, midnight)
        if period == "this_month":
            return dt.datetime.combine(today.replace(day=1), midnight)
        if period == "ytd":
            return dt.datetime.combine(today.replace(month=1, day=1), midnight)
        if period == "all_time":
            return None
        raise ValueError(f"Unknown period '{period}'")

    def time_totals(self, since: Optional[dt.datetime] = None) -> Dict[str, Any]:
        """Tracked seconds within a window, grouped by activity and by axis."""
        by_activity: Counter = Counter()
        by_axis: Counter = Counter()
        total = 0
        for ev in self.state["events"]:
            secs = int(ev.get("seconds", 0))
            if secs <= 0:
                continue
            if since and _parse(ev["timestamp"]) < since:
                continue
            by_activity[ev["name"]] += secs
            by_axis[ev["axis_key"]] += secs
            total += secs
        return {
            "by_activity": dict(by_activity),
            "by_axis": dict(by_axis),
            "total_seconds": total,
        }

    def time_periods(
        self, periods: Optional[List[str]] = None
    ) -> Dict[str, Dict[str, Any]]:
        """Time totals for several windows at once (the /time payload)."""
        periods = periods or ["today", "this_week", "this_month", "ytd", "all_time"]
        return {p: self.time_totals(self.period_start(p)) for p in periods}

    def summary(self) -> Dict[str, Any]:
        """One-shot snapshot for a dashboard / API response."""
        per_axis_events: Dict[str, int] = defaultdict(int)
        for ev in self.state["events"]:
            per_axis_events[ev["axis_key"]] += 1
        return {
            "user": self.state.get("user", "me"),
            "octagon": self.octagon(),
            "counts_all_time": self.counts(),
            "counts_last_7_days": self.counts_last_days(7),
            "events_per_axis": dict(per_axis_events),
            "total_events": len(self.state["events"]),
            "time_this_week_seconds": self.time_totals(
                self.period_start("this_week")
            )["total_seconds"],
        }
