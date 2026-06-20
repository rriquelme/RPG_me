"""RPG_me — turn your life into an 8-axis RPG character sheet.

A small, local-first engine that tracks "skills" across life areas, logs the
routines/events you do, counts how often you do them, and renders the result
as an octagon (radar) chart.

The data model is deliberately plain (dataclasses + a Store interface) so the
same logic can later run inside an AWS Lambda backed by DynamoDB.
"""

from .models import Axis, Skill, level_for_exp, exp_to_next
from .engine import Engine
from .store import JSONStore, MemoryStore, DynamoStore, Store

__all__ = [
    "Axis",
    "Skill",
    "Engine",
    "Store",
    "JSONStore",
    "MemoryStore",
    "DynamoStore",
    "level_for_exp",
    "exp_to_next",
]

__version__ = "0.1.0"
