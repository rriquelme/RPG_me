# RPG_me — Mobile app (Phase 3)

A Flutter app that logs your routines with a tap and draws your octagon
natively with [`fl_chart`](https://pub.dev/packages/fl_chart)'s RadarChart.
One codebase → a real Android `.apk`.

**It runs fully offline.** Everything is computed on-device from a local event
log, so you can use it immediately with no backend. When you later deploy the
[Phase 2 backend](../backend/README.md), add its URL in Settings and tap
**Sync** to push your history up.

```
 ┌─────────────────────────────┐
 │ HomeScreen                  │   octagon (Hours or Levels) + this-week counts
 │   └ FAB "Log" → LogScreen   │   category · name · time spent · date/time
 │   └ ⏱ Timers → TimersScreen │   run several stopwatches at once
 │   └ 🔄 Sync (badge = pending)│   push unsynced events to the backend
 │   └ ⋮ menu                  │   Activity heatmap · Time tracked · Edit axes
 │       · Export CSV (Excel)  │   · Settings
 └──────────────┬──────────────┘
                │ Repository  (local-first)
        ┌───────┴────────┐
        ▼                ▼
   LocalEngine      ApiClient (sync only)
   + LocalStore     POST /sync (idempotent, by client event id)
   (device storage)
```

## What's new in 0.5

- **Octagon uses your axis colours** — the chart is custom-drawn; each axis
  vertex and label is shown in the colour you set in Edit axes.
- **Timers**: each has a **Reset**; pressing **Stop** asks **Save or Discard**;
  **swipe right** on a timer to stop & save, **swipe left** to reveal Delete.
- **"What did you do?" is optional** when logging — blank falls back to the
  category name.
- **Two heatmaps**: a global one plus a second that you can **filter by
  category**.

## What's new in 0.4

- **Octagon by Hours or Levels** — toggle at the top of the home screen.
  "Hours" plots total time spent per axis (the default); "Levels" keeps the
  RPG exp/level view.
- **Multiple timers** — the Timers screen runs several stopwatches at once;
  each banks time against a category and "Stop & save" logs it. Timers are
  persisted (wall-clock based), so they survive backgrounding/restart.
- **Richer logging** — the Log screen records **time spent** (hours/minutes)
  and the **day & time** (date/time picker) so you can review sessions later.
- **Export CSV (Excel)** — menu → *Export CSV*; shares a spreadsheet of every
  logged session (date, time, category, activity, seconds, hours, exp, note).
- **Activity heatmap** — a GitHub-squares calendar of the last ~26 weeks,
  toggleable between time-spent and frequency.

## Editable axes (4–10)

Tap **🎛 Edit axes** to rename, recolour, add, remove, or **reorder** the
octagon's axes — anywhere from 4 to 10 of them. Drag the ☰ handle to change
their order, which is the order they appear around the octagon. The config is
stored on-device (defaults to the classic 8 on first run) and the octagon, log
picker, and timer categories all follow it. When you sync, the app pushes your
axis config to the backend first (`PUT /config`) so custom axes are recognised
server-side. Removing an axis hides it from the octagon; the underlying logged
events are kept.

## Offline-first & sync

- **Reads & writes are local.** `Repository` wraps a `LocalEngine` (a Dart port
  of the backend engine: same exp curve, octagon, counts, streaks, time
  periods) over events persisted with `shared_preferences`. No network needed.
- **Each event gets a stable client id** and a `synced` flag.
- **Sync is push-only and idempotent.** Tapping 🔄 sends unsynced events to
  `POST /sync`; the server skips ids it already has, so re-syncing never
  double-counts. Acknowledged events are marked synced locally.
- An **offline banner** and a **pending-count badge** show sync state.

## What's committed vs. generated

To keep the repo clean, only the **app source** is checked in:

```
app/
  pubspec.yaml          dependencies (http, fl_chart, shared_preferences)
  lib/
    main.dart           app entry + theme
    models.dart         AxisStat / Summary / TimePeriods (shared shapes)
    settings.dart       persisted API base URL (optional) + user id
    repository.dart     local-first data layer + sync()
    local/
      event.dart        on-device event + stable id + synced flag
      local_engine.dart Dart port of the engine (octagon, counts, time…)
      local_store.dart  shared_preferences persistence
    api.dart            ApiClient (used by sync)
    widgets/octagon_chart.dart    the 8-axis RadarChart
    screens/            home, log, timer (stopwatch), time stats, settings
  test/                 local_engine + model parsing tests (`flutter test`)
```

The platform shells (`android/`, `ios/`, …) are **generated** and git-ignored.

## Build the APK

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(`flutter doctor` should be green for Android).

```bash
cd app

# 1. Generate the Android shell. This also overwrites pubspec.yaml/main.dart,
#    so immediately restore RPG_me's versions from git:
flutter create --platforms=android --org com.rpgme --project-name rpg_me .
git checkout -- pubspec.yaml lib/main.dart

# 2. Fetch packages and build
flutter pub get
flutter test                 # runs the model tests
flutter build apk --release  # -> build/app/outputs/flutter-apk/app-release.apk
```

Install the APK on your phone (`flutter install`, or copy the file over).

## First run

Just **Log** something — no setup required. The app starts offline, saves to
the device, and the octagon grows immediately.

When you want your data on a server, open ⚙ **Settings** and paste:

- **API base URL** — the `ApiUrl` from `sam deploy`'s stack outputs
  (e.g. `https://abc123.execute-api.us-east-1.amazonaws.com`).
- **Character / user id** — anything; defaults to `me`.

Then tap 🔄 **Sync** to push your offline history up. Syncing is safe to repeat.

> **Plaintext HTTP note:** the API is HTTPS, so no extra Android config is
> needed. If you ever point the app at a plain-`http://` dev server, add a
> network-security-config exception to the generated `AndroidManifest.xml`.
