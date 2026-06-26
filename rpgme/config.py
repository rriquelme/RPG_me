"""Axis configuration loading.

Axes are data-driven: edit ``data/config.json`` (or pass your own path) to
rename, recolor, or change the 8 life areas without touching code.
"""

from __future__ import annotations

import json
import os
from typing import List

from .models import Axis

DEFAULT_CONFIG_PATH = os.path.join(
    os.path.dirname(os.path.dirname(__file__)), "data", "config.json"
)

# The default octagon: 8 sensible life areas. Rename freely in config.json.
DEFAULT_AXES: List[Axis] = [
    Axis("health", "Health", "Body, fitness, sleep, nutrition", "#DD5555"),
    Axis("mind", "Mind", "Learning, focus, reading", "#4C72B0"),
    Axis("career", "Career", "Work, projects, professional growth", "#55883B"),
    Axis("social", "Social", "Friends, family, relationships", "#E8A33D"),
    Axis("finance", "Finance", "Saving, budgeting, investing", "#2E8B8B"),
    Axis("creativity", "Creativity", "Making, art, music, writing", "#9457A0"),
    Axis("discipline", "Discipline", "Habits, consistency, willpower", "#555555"),
    Axis("spirit", "Spirit", "Meaning, mindfulness, rest", "#C77DB0"),
]


def load_axes(path: str = DEFAULT_CONFIG_PATH) -> List[Axis]:
    """Load the axis configuration, falling back to the defaults."""
    if path and os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as fh:
            raw = json.load(fh)
        axes = [Axis.from_dict(a) for a in raw.get("axes", [])]
        if axes:
            return axes
    return list(DEFAULT_AXES)


def write_default_config(path: str = DEFAULT_CONFIG_PATH) -> None:
    """Materialize the default axis config to disk (so it's easy to edit)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    payload = {"axes": [a.to_dict() for a in DEFAULT_AXES]}
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, ensure_ascii=False)
