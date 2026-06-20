# RPG_me 🎮

Turn your life into an 8-axis RPG character sheet. Log your routines, watch the
counts add up, and see your **octagon** (radar chart) grow as you level up each
area of life.

> Build order: **local engine (this repo) → AWS Lambda backend → Flutter APK.**
> Everything here is local-first and storage/UI agnostic so the same logic moves
> to the cloud and the phone without a rewrite.

## The octagon

Eight life areas, one point each. Each is a *skill* that gains experience and
levels up from the activities you log:

`Health · Mind · Career · Social · Finance · Creativity · Discipline · Spirit`

Axes are **data-driven** — edit [`data/config.json`](data/config.json) to
rename, recolor, or repurpose them.

## Quick start

```bash
pip install -r requirements.txt          # only needed for the chart preview

python cli.py axes                        # list your 8 axes
python cli.py log health gym --exp 15     # record a routine, gain exp
python cli.py log mind read               # default exp = 10
python cli.py status                      # levels + this week's counts
python cli.py streak gym                  # current daily streak
python cli.py chart                       # render octagon.png
python cli.py summary                     # JSON snapshot (what the API returns)
```

State is saved to `data/save_file.json`.

## How it works

| File | Role |
|------|------|
| `rpgme/models.py`  | `Axis`, `Skill`, and the experience/level curve |
| `rpgme/config.py`  | loads the 8 axes from `data/config.json` |
| `rpgme/store.py`   | `Store` interface + `JSONStore` (swap in `DynamoStore` later) |
| `rpgme/engine.py`  | log events, level skills, compute counts/streaks/octagon |
| `rpgme/chart.py`   | local matplotlib radar-chart preview |
| `cli.py`           | command-line front end |

**Counts / frequency:** every `log` appends an event `{axis, name, exp, timestamp}`.
The engine derives totals, "this week" counts, and per-activity daily streaks
from that event log — so adding "how often" stats later is just another query.

## Roadmap

- [x] **Phase 1 — Local engine** (this repo): skills, exp/levels, event log,
      counters/streaks, octagon data + preview chart, CLI, tests.
- [x] **Phase 2 — AWS Lambda backend** (see [`backend/`](backend/)): a
      `DynamoStore(Store)` single-table design plus a Lambda + HTTP API that
      exposes the *same* engine over REST. Deployable with `sam build && sam
      deploy`. The engine code was reused unchanged. See
      [backend/README.md](backend/README.md).
- [ ] **Phase 3 — Flutter APK.** A mobile app that calls the API, logs routines
      with a tap, and draws the octagon natively (`fl_chart` RadarChart). One
      codebase → a real `.apk`.

## Tests

```bash
python -c "import tests.test_engine as t; [getattr(t,n)() for n in dir(t) if n.startswith('test_')]"
```
(or `pytest tests/` if you have pytest installed)
