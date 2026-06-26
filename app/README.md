# RPG_me — Mobile app (Phase 3)

A Flutter app that talks to the [Phase 2 backend](../backend/README.md), logs
your routines with a tap, and draws your octagon natively with
[`fl_chart`](https://pub.dev/packages/fl_chart)'s RadarChart. One codebase →
a real Android `.apk`.

```
 ┌─────────────────────────────┐
 │ HomeScreen                  │   octagon (RadarChart) + this-week counts
 │   └ FAB "Log" → LogScreen   │   pick axis · name · exp slider
 │   └ ⏱ Timer → TimerScreen   │   stopwatch → confirm → file under a category
 │   └ 📊 Time → TimeScreen     │   tracked time: today/week/month/YTD/all-time
 │   └ ⚙ Settings → API URL    │   stored via shared_preferences
 └──────────────┬──────────────┘
                │ ApiClient (http)
                ▼
   GET /summary · /axes · /time · POST /log (seconds) · GET /streak/{name}
```

## What's committed vs. generated

To keep the repo clean, only the **app source** is checked in:

```
app/
  pubspec.yaml          dependencies (http, fl_chart, shared_preferences)
  lib/
    main.dart           app entry + theme
    models.dart         AxisStat / Summary / TimePeriods (mirror the API JSON)
    settings.dart       persisted API base URL + user id
    api.dart            ApiClient (summary, axes, log, time, streak)
    widgets/octagon_chart.dart    the 8-axis RadarChart
    screens/            home, log, timer (stopwatch), time stats, settings
  test/models_test.dart JSON-parsing tests (run with `flutter test`)
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

The app opens a **Settings** dialog. Paste:

- **API base URL** — the `ApiUrl` from `sam deploy`'s stack outputs
  (e.g. `https://abc123.execute-api.us-east-1.amazonaws.com`).
- **Character / user id** — anything; defaults to `me`.

Then tap **Log** to record a routine and watch the octagon grow. Pull down to
refresh.

> **Plaintext HTTP note:** the API is HTTPS, so no extra Android config is
> needed. If you ever point the app at a plain-`http://` dev server, add a
> network-security-config exception to the generated `AndroidManifest.xml`.

## Try it without a backend

To demo the UI before deploying AWS, run the backend locally with
`sam local start-api` (see [../backend/README.md](../backend/README.md)) and
set the base URL to the printed `http://127.0.0.1:3000` (allow cleartext as
noted above).
