"""Core domain models for RPG_me.

These are intentionally free of any storage or rendering concerns so they can
be reused unchanged in a CLI, a local app, or an AWS Lambda handler.
"""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Any, Dict


# --- Experience curve -------------------------------------------------------
#
# The original prototype used exp_next = lvl * base * 2**(lvl-1), which grows so
# fast it becomes unreachable after a few levels. We keep a configurable base
# but use a gentler quadratic-ish curve that still rewards consistency.

BASE_EXP_PER_LEVEL = 50


def exp_to_next(level: int, base: int = BASE_EXP_PER_LEVEL) -> int:
    """Experience required to advance *from* the given level to the next one."""
    if level < 1:
        level = 1
    # Smoothly increasing: lvl 1->2 costs `base`, and each level adds ~50%.
    return int(base * level * 1.5)


def level_for_exp(total_exp: int, base: int = BASE_EXP_PER_LEVEL) -> int:
    """Return the level reached for a given cumulative experience total."""
    level = 1
    remaining = max(0, int(total_exp))
    while remaining >= exp_to_next(level, base):
        remaining -= exp_to_next(level, base)
        level += 1
    return level


def exp_into_level(total_exp: int, base: int = BASE_EXP_PER_LEVEL) -> int:
    """Experience accumulated *within* the current level (progress bar value)."""
    level = 1
    remaining = max(0, int(total_exp))
    while remaining >= exp_to_next(level, base):
        remaining -= exp_to_next(level, base)
        level += 1
    return remaining


# --- Axis (one of the 8 sides of the octagon) -------------------------------


@dataclass
class Axis:
    """One life area = one point on the octagon."""

    key: str
    label: str
    description: str = ""
    color: str = "#4C72B0"

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "Axis":
        return cls(
            key=d["key"],
            label=d.get("label", d["key"].title()),
            description=d.get("description", ""),
            color=d.get("color", "#4C72B0"),
        )

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# --- Skill (the live state of one axis) -------------------------------------


@dataclass
class Skill:
    """The accumulated state of a single axis: total exp -> level."""

    axis_key: str
    total_exp: int = 0

    @property
    def level(self) -> int:
        return level_for_exp(self.total_exp)

    @property
    def exp_into_level(self) -> int:
        return exp_into_level(self.total_exp)

    @property
    def exp_to_next(self) -> int:
        return exp_to_next(self.level)

    def gain_exp(self, amount: int) -> None:
        self.total_exp += max(0, int(amount))

    def to_dict(self) -> Dict[str, Any]:
        return {
            "axis_key": self.axis_key,
            "total_exp": self.total_exp,
            "level": self.level,
            "exp_into_level": self.exp_into_level,
            "exp_to_next": self.exp_to_next,
        }
