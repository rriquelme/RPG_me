"""Tests for the RPG_me engine and exp curve."""

import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from rpgme.engine import Engine  # noqa: E402
from rpgme.models import level_for_exp, exp_to_next  # noqa: E402
from rpgme.store import MemoryStore  # noqa: E402


def test_exp_curve_monotonic():
    assert level_for_exp(0) == 1
    assert level_for_exp(exp_to_next(1)) == 2
    # Cost to advance should never decrease.
    costs = [exp_to_next(l) for l in range(1, 10)]
    assert costs == sorted(costs)


def test_log_awards_exp_and_levels():
    eng = Engine(MemoryStore())
    eng.log("health", "gym", exp=exp_to_next(1))
    assert eng.skill("health").level == 2


def test_unknown_axis_rejected():
    eng = Engine(MemoryStore())
    try:
        eng.log("nonsense", "thing")
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError for unknown axis")


def test_counts_and_octagon():
    eng = Engine(MemoryStore())
    eng.log("mind", "read")
    eng.log("mind", "read")
    eng.log("health", "gym")
    assert eng.counts()["read"] == 2
    assert eng.counts()["gym"] == 1
    oct_ = {a["key"]: a for a in eng.octagon()}
    assert len(oct_) == 8
    assert oct_["mind"]["total_exp"] == 20


def test_streak_counts_consecutive_days():
    eng = Engine(MemoryStore())
    today = dt.date.today()
    for back in (2, 1, 0):
        ts = (
            dt.datetime.combine(today - dt.timedelta(days=back), dt.time(8))
        ).isoformat()
        eng.log("health", "gym", timestamp=ts)
    assert eng.streak("gym") == 3


def test_default_octagon_has_eight_axes():
    eng = Engine(MemoryStore())
    assert len(eng.octagon()) == 8
