"""Render the octagon (radar) chart from engine data.

Uses matplotlib with the headless 'Agg' backend so it works on a server or in
CI. The mobile app will later draw the same `octagon()` data natively
(e.g. fl_chart's RadarChart in Flutter) — this is the local preview.
"""

from __future__ import annotations

import math
from typing import Any, Dict, List, Optional


def render_octagon(
    octagon: List[Dict[str, Any]],
    out_path: str = "octagon.png",
    title: str = "RPG_me",
    max_level: Optional[int] = None,
) -> str:
    """Draw the radar chart and write it to ``out_path``. Returns the path."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    labels = [a["label"] for a in octagon]
    levels = [a["level"] for a in octagon]
    n = len(labels)
    if n == 0:
        raise ValueError("No axes to plot.")

    ceiling = max_level or max(5, max(levels) + 1)

    # Close the loop.
    angles = [i / n * 2 * math.pi for i in range(n)]
    angles += angles[:1]
    values = levels + levels[:1]

    fig, ax = plt.subplots(figsize=(6, 6), subplot_kw={"polar": True})
    ax.set_theta_offset(math.pi / 2)
    ax.set_theta_direction(-1)

    ax.plot(angles, values, color="#4C72B0", linewidth=2)
    ax.fill(angles, values, color="#4C72B0", alpha=0.25)

    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(labels, fontsize=10)
    ax.set_ylim(0, ceiling)
    ax.set_yticks(range(0, ceiling + 1, max(1, ceiling // 5)))
    ax.set_title(title, fontsize=15, pad=20)
    ax.grid(True, alpha=0.4)

    fig.tight_layout()
    fig.savefig(out_path, dpi=120, bbox_inches="tight")
    plt.close(fig)
    return out_path
