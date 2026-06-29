# Contributing to RPG_me

Thanks for hacking on RPG_me! This guide covers local setup, the branching
model, and how releases work.

## Project layout

| Path | What |
|------|------|
| [`rpgme/`](rpgme/) | Python engine (categories, events, exp/levels, counts, streaks, time, octagon). Pure stdlib. |
| [`backend/`](backend/) | AWS SAM stack (Lambda + API Gateway + DynamoDB) wrapping the engine. Optional — only for sync. |
| [`app/`](app/) | Flutter app (offline-first). A Dart port of the engine runs on-device. |
| [`tests/`](tests/) | Python tests for the engine and the Lambda handler. |

## Local setup

### Python engine

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt          # only needed for the chart preview
# run the tests:
python -c "import tests.test_engine as t; [getattr(t,n)() for n in dir(t) if n.startswith('test_')]"
python -c "import sys; sys.path.insert(0,'backend'); import tests.test_handler as t; [getattr(t,n)() for n in dir(t) if n.startswith('test_')]"
```

### Flutter app

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(`flutter doctor` green for Android). Only the app source is committed; the
Android shell is generated:

```bash
cd app
flutter create --platforms=android --org com.rpgme --project-name rpg_me .
git checkout -- pubspec.yaml lib/main.dart analysis_options.yaml
rm -f test/widget_test.dart
# Some plugins (file_picker) require compileSdk 36 — bump it if lower:
sed -i 's/compileSdk = flutter.compileSdkVersion/compileSdk = 36/' android/app/build.gradle.kts 2>/dev/null || true
flutter pub get
flutter test
flutter run            # or: flutter build apk --release
```

The CI workflow does exactly this (see
[`.github/workflows/release-apk.yml`](.github/workflows/release-apk.yml)); if a
build issue is environment-specific, check there first.

### Backend (optional)

```bash
cd backend
sam build && sam deploy --guided
```

## Branching model

- **`dev`** is the default branch — the integration branch and the **release
  branch**.
- Branch off `dev` for changes:
  ```bash
  git checkout dev && git pull
  git checkout -b feature/short-description
  ```
- Open a pull request **into `dev`**. Keep PRs focused; describe the change.

## Releases

CI builds the Android APK and publishes a GitHub Release when **any** of these
happen on `dev` (or `main`):

- a commit message contains **`[release]`**, or
- an **`app-vX.Y.Z`** tag is pushed, or
- the workflow is run manually (**Actions → Build & Release APK → Run workflow**).

To cut a versioned release:

1. Bump the version in [`app/pubspec.yaml`](app/pubspec.yaml)
   (`version: X.Y.Z+N`).
2. Bump the fallback tag in the workflow (`app-vX.Y.Z`) so a `[release]` build
   tags correctly.
3. Merge to `dev` with `[release]` in the message (or push the tag).

Without a release trigger, pushes still build the APK (uploaded as a workflow
artifact) but don't publish a Release.

> Note: a transient GitHub "tag not yet discoverable" race can occasionally
> leave a release as a draft. If that happens, re-run the workflow run and it
> publishes cleanly.

## Tests & checks

- **Python:** run the two test modules above (engine + handler).
- **Flutter:** `cd app && flutter test`.
- Please keep both green before opening a PR.

## Recommended branch protection for `dev`

Set these in **Settings → Branches → Add rule** for `dev` (owner-only; can't be
done via API):

- ✅ **Require a pull request before merging.**
- ✅ **Require status checks to pass** → select the **`build`** check from
  *Build & Release APK*.
- ✅ **Require branches to be up to date before merging** (optional).
- ✅ **Require linear history** (optional, keeps history tidy).
- ✅ **Do not allow force pushes / deletions.**
