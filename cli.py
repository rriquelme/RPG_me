#!/usr/bin/env python3
"""RPG_me command-line interface.

Examples:
    python cli.py axes                      # list the 8 octagon axes
    python cli.py log health gym --exp 15   # record a routine, gain exp
    python cli.py log mind read             # default exp = 10
    python cli.py status                     # show levels + counters
    python cli.py streak gym                 # current daily streak
    python cli.py chart                      # render octagon.png
    python cli.py init-config                # write data/config.json to edit
"""

from __future__ import annotations

import argparse
import json

from rpgme.config import load_axes, write_default_config, DEFAULT_CONFIG_PATH
from rpgme.engine import Engine
from rpgme.store import JSONStore

SAVE_PATH = "data/save_file.json"


def _engine() -> Engine:
    return Engine(JSONStore(SAVE_PATH))


def cmd_axes(_args) -> None:
    for a in load_axes():
        print(f"  {a.key:12} {a.label:12} {a.description}")


def cmd_log(args) -> None:
    eng = _engine()
    if args.seconds > 0:
        ev = eng.log_time(
            args.axis,
            args.name,
            args.seconds,
            exp=args.exp if args.exp is not None else None,
            note=args.note or "",
        )
    else:
        ev = eng.log(args.axis, args.name, exp=args.exp or 10, note=args.note or "")
    eng.save()
    sk = eng.skill(args.axis)
    print(
        f"+{ev['exp']} exp to {args.axis} via '{ev['name']}' "
        f"-> level {sk.level} ({sk.exp_into_level}/{sk.exp_to_next})"
    )


def cmd_status(_args) -> None:
    eng = _engine()
    s = eng.summary()
    print(f"Character: {s['user']}  ({s['total_events']} events logged)\n")
    print("Octagon:")
    for a in s["octagon"]:
        bar = "█" * a["level"]
        print(f"  {a['label']:12} L{a['level']:<2} {bar}")
    if s["counts_last_7_days"]:
        print("\nThis week:")
        for name, n in sorted(
            s["counts_last_7_days"].items(), key=lambda x: -x[1]
        ):
            print(f"  {name:16} x{n}")


def cmd_streak(args) -> None:
    print(f"{args.name}: {_engine().streak(args.name)} day streak")


def _fmt_hms(seconds: int) -> str:
    h, rem = divmod(int(seconds), 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}h {m}m"
    if m:
        return f"{m}m {s}s"
    return f"{s}s"


def cmd_time(args) -> None:
    eng = _engine()
    periods = eng.time_periods()
    labels = {
        "today": "Today",
        "this_week": "This week",
        "this_month": "This month",
        "ytd": "Year to date",
        "all_time": "All time",
    }
    for key, label in labels.items():
        data = periods[key]
        if args.name:
            secs = data["by_activity"].get(args.name.strip().lower(), 0)
            print(f"  {label:14} {_fmt_hms(secs)}")
        else:
            print(f"{label}: {_fmt_hms(data['total_seconds'])}")
            for name, secs in sorted(
                data["by_activity"].items(), key=lambda x: -x[1]
            ):
                print(f"    {name:16} {_fmt_hms(secs)}")


def cmd_chart(args) -> None:
    from rpgme.chart import render_octagon

    eng = _engine()
    path = render_octagon(eng.octagon(), out_path=args.out)
    print(f"Wrote {path}")


def cmd_summary(_args) -> None:
    print(json.dumps(_engine().summary(), indent=2, ensure_ascii=False))


def cmd_init_config(_args) -> None:
    write_default_config()
    print(f"Wrote {DEFAULT_CONFIG_PATH} — edit it to customize your 8 axes.")


def main() -> None:
    p = argparse.ArgumentParser(prog="rpg_me", description="RPG your life.")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("axes", help="list octagon axes").set_defaults(fn=cmd_axes)

    lg = sub.add_parser("log", help="log a routine/activity")
    lg.add_argument("axis", help="axis key (see `axes`)")
    lg.add_argument("name", help="what you did, e.g. gym/read/meditate")
    lg.add_argument("--exp", type=int, default=None)
    lg.add_argument("--seconds", type=int, default=0, help="tracked duration of a timed session")
    lg.add_argument("--note", default="")
    lg.set_defaults(fn=cmd_log)

    sub.add_parser("status", help="levels + weekly counts").set_defaults(fn=cmd_status)

    st = sub.add_parser("streak", help="daily streak for an activity")
    st.add_argument("name")
    st.set_defaults(fn=cmd_streak)

    tm = sub.add_parser("time", help="tracked time per period")
    tm.add_argument("name", nargs="?", help="optional: one activity across periods")
    tm.set_defaults(fn=cmd_time)

    ch = sub.add_parser("chart", help="render octagon.png")
    ch.add_argument("--out", default="octagon.png")
    ch.set_defaults(fn=cmd_chart)

    sub.add_parser("summary", help="JSON snapshot").set_defaults(fn=cmd_summary)
    sub.add_parser("init-config", help="write editable axis config").set_defaults(
        fn=cmd_init_config
    )

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
