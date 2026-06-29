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

## What's new in 0.31

- The top **+** on the home screen now logs directly (same as the Log button).
- Removed the **"me ·"** prefix before the events count.
- In **Categories**: a category's **+** adds a subcategory **inline** right under
  it (no popup) — rename it by tapping the name, just like categories
  (subcategory rename pen is gone). The **Add category** button opens a popup to
  type the name and pick a colour.

## What's new in 0.30

- **One unified Categories screen.** No more Categories/Subcategories tabs —
  every category and its (indented) subcategories show on a single screen. Each
  category has a **+** to add a subcategory to it. Drag the ☰ handle to reorder
  anything: a subcategory can move within its category **or onto another
  category**, and a category moves together with its subcategories.
- The **Add category** switch still puts its button next to **Save** (off) or at
  the bottom (on). The **Add subcategory** switch adds an optional bottom
  *Add subcategory* button (pick a category) — subcategories never get a button
  next to Save, since every category already has its own **+**.

## What's new in 0.29

- **Add-category / Add-subcategory buttons moved to where they belong.** They no
  longer appear on the home screen. Their Settings switches now control the
  **Edit categories** screen: off → a **+** sits next to **Save**; on → the
  **Add** button shows at the bottom of that tab. The home **Log** button is
  unchanged.
- **App bar tidied** — the **RPG_me** title is gone; order is now **+ · Timers ·
  Activity · Edit categories · Settings · ⋮**, and the ⋮ menu also lists *Edit
  categories* and *Settings* explicitly.
- **Sync merged into Settings** — there's a **Sync now** button in Settings →
  API settings; Sync is no longer a separate top-bar item.

## What's new in 0.28

- **Top app bar redesign** — a **+** menu (Log activity · Add category · Add
  subcategory), a dedicated **Edit categories** icon, and a **⚙ Settings** gear.
  Sync moved into the ⋮ menu (its pending-count badge is gone), and the offline
  banner is hidden.
- **Configurable bottom buttons** — Settings → *Bottom buttons* toggles the
  **Log / Add category / Add subcategory** quick buttons at the bottom of the
  home screen. Only **Log** is on by default; all actions stay available from
  the top **+** menu.
- **Activity screen** — the separate "All activity" grid is gone; the Category
  picker now starts on **All** (every category) and you drill in from there.
- **Octagon** — the **Hours** toggle is now labelled **Time**.
- **Day numbers** — Settings → *Activity* → *Show day numbers* prints the
  day-of-month in each heatmap cell.

## What's new in 0.27

- **Percentage respects Avg / day** now (like the other metrics), instead of
  ignoring it.
- **"Now" jump** — when you've navigated the octagon window into the past, a
  **Now** link appears under the ‹ › label; tapping it brings the window back to
  the present (today / current week / month / year, or re-anchors a custom day
  or range to include today).

## What's new in 0.26

- **Reworked octagon period picker + always-on navigation.** The dropdown is now
  **Today · This week · This month · This year · All time · Custom: single day ·
  Custom: range of days** (the rolling "last N days / year to date" options were
  removed). The **‹ ›** arrows are always shown and step the window by its own
  unit — day by day for *Today*, week by week for *This week*, then month, year,
  or by the custom day/range you picked. (Disabled for *All time*.)

## What's new in 0.25

- **Optional Number & Percentage metrics** (off by default) — Settings →
  *Extra metrics* has **Track number** and **Track percentage** switches. Each
  one you enable adds a field on the Log screen and a metric to the octagon
  toggle (**Frequency · Hours · Number · Percent**). Numbers are **summed** per
  category; percentages are **averaged** (and ignore Avg/day). They can be mixed
  freely on the dashboard.
- **Today** is now an option in the octagon period dropdown.

## What's new in 0.24

- **Custom time window** — next to *Avg / day* there's now a **Custom** chip.
  Tap it to pick **a single day** or **a range of days**; the octagon then shows
  exactly that window. Under the chart, **‹ ›** arrows step the window by its own
  length (previous/next day, or previous/next range), with a **Clear** link to
  return to the preset periods.

## What's new in 0.23

- **Timers get subcategories** — the New/Edit timer dialogs now have a
  Subcategory picker just like the Log screen (None by default, then the
  subcategories, then **Create new…**). The chosen subcategory is saved with the
  session when you stop the timer, and shows on the timer card.
- **“All subcategories (inc. hidden)”** — the Activity screen's *By subcategory*
  dropdown adds this option after *All subcategories*, so you can see the
  dominant-by-day view including hidden subcategories.

## What's new in 0.22

- **Log screen dashboard: one chart, switched by the picker** — the Subcategory
  dropdown now defaults to **None** (no more "All subcategories"). With None,
  the dashboard shows the **category** activity; pick a subcategory and it
  **replaces** that with the subcategory's activity (one chart at a time). Still
  gated by the "View dashboard on log creation" setting.

## What's new in 0.21

- **Subcategory heatmap on the Activity screen** — the Activity screen now has a
  third **“By subcategory”** calendar under *All activity* and *By category*. It
  follows the selected category and defaults to **all subcategories**, colouring
  each day by the one you logged most; pick a specific subcategory to drill in.

## What's new in 0.20

- **Create a subcategory while logging** — the Subcategory dropdown is now
  always shown, and its last item is **“Create new…”**. It opens a quick
  name + colour dialog, adds the subcategory to that category, and
  auto-selects it. Works even when the category had none yet.
- **Unsaved-changes prompt** — leaving *Edit categories* (in either the
  Categories or Subcategories tab) with unsaved edits now asks **Save /
  Discard / Cancel**.

## What's new in 0.19

- **Hide a whole subcategory from the charts** — in *Edit categories →
  Subcategories*, each subcategory has a 👁 eye toggle. Hiding one keeps it
  loggable but drops its entries from the octagon and the subcategory
  dashboard. You can now hide at three levels: a **category**, a
  **subcategory**, or a **single log entry**.

## What's new in 0.18

- **Subcategories now have their own editor and colours** — *Edit categories*
  has a **Categories / Subcategories** toggle at the top. In Subcategories mode,
  pick a category and rename, recolour, add, remove, or reorder its
  subcategories, just like categories. A blank colour inherits the category's.
- **Coloured subcategory dashboard** — on the Log screen, the subcategory
  activity chart uses each subcategory's colour.
- **"All subcategories" by default** — instead of an empty prompt, the
  subcategory chart now defaults to **all subcategories**, colouring each day by
  the subcategory you logged most that day. Pick a specific one to drill in.

## What's new in 0.17

- **"Hide this entry from the chart"** — the Log screen tick now hides just
  **that one entry** from the octagon (it's still logged and counted in the
  heatmap, history, and time totals). It no longer changes the whole category.
  Hiding a whole category still lives in *Edit categories* (the 👁 eye).
- **Separate subcategory activity dashboard** — when "View dashboard on log
  creation" is on, the category's activity heatmap shows on top, and (if the
  category has subcategories) a **second chart** below shows the picked
  subcategory's activity. It defaults to none until you choose a subcategory.

## What's new in 0.16

- **Activity dashboard on the Log screen** — with "View dashboard on log
  creation" enabled, the top of the Log screen shows the **activity heatmap**
  of the selected category, refreshing live as you change the selection.

## What's new in 0.15

- **Hide a category from the chart** — in *Edit categories*, tap the 👁 eye to
  hide an axis from the octagon. It stays fully loggable; it just isn't drawn.
  The Log screen has the same **"Hide from chart"** tick for the selected
  category.
- **Subcategories** — give any category optional subcategories (none by
  default), managed from the same *Edit categories* menu. When logging a
  category that has them, pick a subcategory (optional).

## What's new in 0.14

- **Tap a category on the octagon** to open a new log with that category
  already selected — the **+ Log** button stays for picking from scratch.
- **Optional category dashboard on the Log screen** — a per-category summary
  (this week / all-time counts & time, level, last logged) at the top of the
  Log screen. Off by default; enable **Settings → "View dashboard on log
  creation"**.

## What's new in 0.13

- **Heatmap fixed** — it's now a proper **month calendar**: every day sits in
  its real weekday row, with blank cells padding the partial first/last weeks,
  so months separate naturally (no more "every month starts Monday"). Each
  month has its name on top; it auto-scrolls to the current month.

## What's new in 0.12

- **Edit a running timer's category** (and name) — keeps the elapsed time.
- **Minimum categories lowered to 3** (3–10).
- **"This week"** octagon period (since your week's first day), and a
  **first-day-of-week** setting (Mon–Sun) in Settings.
- **Heatmap split by month** — an empty column between months with the month
  name on top; weekday labels follow your first-day-of-week; auto-scrolls to
  the most recent week.

## What's new in 0.11

- **Edit categories** moved back to the ⋮ menu (renamed from "Edit axes").
- **Levels hidden** for now — the octagon toggle is just **Frequency / Hours**,
  and switching no longer resizes the chart (`showSelectedIcon` off).
- **Timers redesigned** — bigger, clearer cards with visible Reset / Pause /
  Stop buttons, and the running time now shows **milliseconds** (ticking fast).

## What's new in 0.10

- **Edit axes moved into Settings**, alongside the renamed **API settings**.
- **Export / Import logs (Markdown)** replaces the CSV export. Export shares
  the standard `data.md`; Import replaces this device's data from a previously
  exported `.md` — the format is stable across versions for portability.
- **Home screen**: the "this week" list is gone; a **View logs** button (and
  the new menu items) take its place.

## What's new in 0.9

- **Frequency is the default** for the octagon and the heatmap.
- **Heatmap upgrades**: weekday labels (M–S) down the left; **tap any day** to
  see that day's frequency and time spent; coloured by frequency — one log is
  a light cell, more logs are progressively darker (1 / 2 / 3 / 4+).
- **Markdown storage**: data is now saved as `rpg_me/data.md` — a readable
  table of your logged activities plus JSON blocks as the source of truth.
  Migrated automatically from the previous file.

## What's new in 0.8

- **Frequency octagon** — the home toggle is now **Hours · Frequency ·
  Levels**. "Frequency" plots how many times you logged each category in the
  window, so a duration-less tally (0h 0m, no description — just a category)
  now visibly moves the chart. Works with the period window and Avg/day.

## What's new in 0.7

- **Durable storage** — data now lives in a JSON file in the app's documents
  folder (`rpg_me/data.json`) instead of shared_preferences, so it survives
  app updates. Existing data is migrated automatically on first launch.
- **Heatmap shortcut** — a calendar icon in the top bar opens the activity
  heatmap directly.
- **Optional timer activity** — naming a new timer is optional (falls back to
  the category).
- **Edit logged entries** — tap (or the edit icon) on a row in *Logged
  activities* to change its category, name, duration, or date/time.

## What's new in 0.6

- **Optional axis colours** — Edit axes → tap a colour → **Default** to clear
  it (the axis then uses a neutral colour).
- **Logged activities** — menu → *Logged activities*: a history of every
  session (date, time, category, duration) with delete.
- **Coloured heatmaps** — the global grid is green; the per-category grid uses
  that axis's colour.
- **Configurable octagon window** — a period dropdown on the home screen:
  Last 7 days · This month · Last 30 days · Year to date · Last year · All
  time. The choice is saved.
- **Average per day** — an "Avg / day" toggle divides the octagon values by the
  number of days in the window (e.g. average hours/day).

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

# 2. Some plugins (file_picker) require compileSdk 36 — bump it if your
#    generated template is lower:
sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/' \
  android/app/build.gradle.kts 2>/dev/null || true

# 3. Fetch packages and build
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
