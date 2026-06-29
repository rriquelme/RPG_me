# RPG_me 🎮

**Turn your life into an editable radar "octagon."** Log your routines and the
time you spend, then watch each life category grow on a custom radar chart —
with a GitHub-style activity heatmap, a multi-stopwatch timer, and your data in
a plain Markdown file you own.

It's an **offline-first Android app** (no account, no backend needed) backed by
a small Python engine, with an **optional** AWS cloud for syncing across
devices.

> **About (for the GitHub repo description):**
> RPG_me — turn your life into an editable radar "octagon." Offline-first
> Android app to log routines & time, track frequency/hours per category, with a
> GitHub-style activity heatmap, a multi-timer stopwatch, and Markdown
> export/import. Optional AWS (Lambda + DynamoDB) sync. Python engine + Flutter app.

---

## 📲 Get the app

Download the latest signed APK from **[Releases](../../releases/latest)**
(`rpg_me.apk`).

1. Open the release on your Android phone and download `rpg_me.apk`.
2. When prompted, allow **“install unknown apps”** for your browser/file manager
   (the APK is debug-signed — fine for personal use).
3. Open it, tap **Log**, and you're tracking. No setup, fully offline.

> Installing a new version? **Install it as an update** (don't uninstall first)
> so your data migrates.

---

## ✨ Features

- **The octagon** — a radar chart of your life categories. Toggle between
  **Frequency** (how often you log each one) and **Hours** (time spent).
- **Editable categories (4–10)** — rename, recolour, add/remove, and drag to
  reorder. Colours are optional.
- **Flexible logging** — a tap-to-log entry with an optional name, optional
  duration (hours/minutes), and a date/time picker so you can backfill.
- **Multiple timers** — run several stopwatches at once (millisecond display);
  “Stop” asks to save or discard, and the time is filed under a category.
- **Activity heatmap** — a GitHub-contributions calendar, by frequency or time
  spent, globally and per category; tap a day for its totals.
- **Configurable window + averages** — view the octagon over the last 7/30
  days, this month, YTD, last year, or all time — optionally as a per-day
  average.
- **Logged history** — review, edit, or delete any past entry.
- **Your data, in Markdown** — everything lives in `rpg_me/data.md` on the
  device (a readable table + JSON blocks). **Export / Import** it as a `.md`
  file; the format is stable across versions.
- **Optional sync** — point the app at an AWS backend and push your history
  (idempotent, so re-syncing never double-counts).

---

## 🧱 How it's built

Three layers that share one source of truth — the engine logic:

| Layer | Path | What it is |
|-------|------|------------|
| **Engine** | [`rpgme/`](rpgme/) | Pure-Python core: categories, events, exp/levels, counts, streaks, time periods, the octagon. Storage- and UI-agnostic. |
| **Backend** | [`backend/`](backend/) | The same engine behind an AWS **Lambda + API Gateway + DynamoDB** stack (SAM-deployable). Optional — only for sync. See [backend/README.md](backend/README.md). |
| **App** | [`app/`](app/) | An offline-first **Flutter** app. A Dart port of the engine runs entirely on-device; sync is optional. Builds the Android APK. See [app/README.md](app/README.md). |

---

## 🛠️ Build & develop

### The app (Android APK)

The APK is built in CI on every push (see
[`.github/workflows/release-apk.yml`](.github/workflows/release-apk.yml)) and
attached to a Release. To build locally you need the
[Flutter SDK](https://docs.flutter.dev/get-started/install); see
[app/README.md](app/README.md) for the exact steps.

### The Python engine (CLI)

Useful for trying the core logic without the app:

```bash
pip install -r requirements.txt          # only needed for the chart preview
python cli.py axes                        # list categories
python cli.py log health gym --seconds 1800   # log 30 min to "health"
python cli.py time                        # time tracked per period
python cli.py status                      # levels + this week's counts
python cli.py chart                       # render octagon.png
```

### The backend (AWS)

```bash
cd backend
sam build && sam deploy --guided
```

Then put the output `ApiUrl` into the app's **API settings** and tap **Sync**.
Full details in [backend/README.md](backend/README.md).

---

## ✅ Tests

```bash
# Python engine + Lambda handler
python -c "import tests.test_engine as t; [getattr(t,n)() for n in dir(t) if n.startswith('test_')]"

# Flutter (from app/)
cd app && flutter test
```

---

## 🌿 Branches & releases

- **`dev`** is the default branch and the integration branch for new work and
  **future releases**.
- A push to `dev`/`main` with a `[release]` commit (or an `app-vX.Y.Z` tag, or a
  manual workflow run) triggers CI to build the APK and publish a GitHub
  Release. Release tags follow `app-vMAJOR.MINOR.PATCH` (e.g. `app-v0.11.0`).
- See **[CONTRIBUTING.md](CONTRIBUTING.md)** for local setup, the branching
  model, the release checklist, and recommended `dev` branch protection.

---

*Built with [Claude Code](https://claude.com/claude-code).*
