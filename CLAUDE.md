# flutter-ai-testing

## What this is
An MCP server and kit that make any Flutter app testable by any AI agent: start the app on a
device, tap and type by test key, `where_am_i`, setup and UI-only tools, key checks. Apps get
copies through `install.sh`; see `README.md`.

## Stack
- Language / framework: Dart / Flutter (library, example app), Bash, Python 3 (scripts).
- Database / services: none. Talks to `marionette_mcp` and the Dart VM service locally.
- Hosting / deploy: private repo `ENGR-JELH/flutter-ai-testing`. No releases; apps run `install.sh`.

## Commands
- Install: `flutter pub get`
- Dev: `cd example && bash scripts/ai-testing/marionette-run.sh <device-id>`
- Test: `flutter analyze && flutter test`, then `cd example && flutter analyze`; the server
  is tested by driving `example/` through it (start_app, taps, where_am_i, stop_app)
- Lint / format: `dart format lib test example/lib example/marionette`
- Build / deploy: none. After changing `lib/` or `scripts/`, bump `VERSION` and re-run
  `bash install.sh example` so the example has the new copies.

## Structure
- `mcp/server.py` — the MCP server (installed as `scripts/ai-testing/mcp_server.py`). Standard library only.
- `lib/flutter_ai_testing.dart` — the agent tools (installed into apps as `marionette/ai_testing.dart`).
- `scripts/` — launch script and key scripts (installed into `scripts/ai-testing/`).
- `tools/` — Marionette CLI and VM-service reader (installed next to the scripts).
- `templates/` — starting files `install.sh` adds only when missing.
- `example/` — a small app with everything installed and filled in. Invented data only.
- `test/` — library tests.

## Conventions
- Stay generic: no company, product, host or app id from any app that uses the kit. App specifics
  belong in the app's `ai-testing.conf` and `marionette/app_tools.dart`.
- Tools return only non-personal facts (route names, keys, booleans, codes). Never add a log
  collector or anything that returns on-screen text wholesale.
- The installed copies must keep working without this repo: no package dependency on it, and
  only `flutter`, `marionette_flutter` and Python's standard library (`vmeval.py` also needs
  `websockets`).
- Commits: short imperative subject. Personal GitHub account, personal email.

## Gotchas
- `marionette_flutter` in an app must match the `marionette_mcp` version on the machine (0.7.0).
- `MarionetteBinding.ensureInitialized` must run before the app's own start-up, or apps that
  start inside their own zone (crash reporters) create a second binding.
- iOS simulator permission changes end the running app, so the launch script grants them before
  launch. Android grants need the app installed, so they run after.
- On Android, Back on the first page closes the app.
