# flutter_ai_testing

## What this is
A Flutter dev-dependency package that makes any Flutter app testable by any AI agent: an MCP
server (`dart run flutter_ai_testing:mcp`) that starts the app on a device and drives it, plus
the in-app tools (`runWithAiTesting`: `whereAmI`, setup and UI-only shortcuts) and key checks.
See `README.md`.

## Stack
- Dart / Flutter. `lib/src/app/` uses Flutter (runs in the app); `lib/src/cli/` and `bin/` are
  pure Dart (run on the machine). Never import Flutter from `lib/src/cli/` or `bin/`.
- Depends on `marionette_flutter` and `marionette_mcp`, pinned to the same version. The server
  runs `marionette_mcp` from the app's own package config, so versions always match.
- Hosting: `ENGR-JELH/flutter-ai-testing`; meant for pub.dev (`dart pub publish`, by the owner).

## Commands
- Install: `flutter pub get`
- Test: `flutter analyze && flutter test`, then `cd example && flutter pub get && flutter analyze marionette lib`
- Live test: drive `example/` through the server on an emulator (start_app, taps, where_am_i, stop_app)
- Lint / format: `dart format lib bin test example/lib example/marionette`
- Release: bump `version` in `pubspec.yaml` and `serverVersion` in `lib/src/cli/mcp_server.dart`, add a `CHANGELOG.md` entry

## Structure
- `lib/flutter_ai_testing.dart` — public API: `runWithAiTesting`, `AiTestingConfig`, `GoRouterTools`, `MarionetteConfiguration`.
- `lib/src/app/` — in-app tools (Flutter).
- `lib/src/cli/` — conf reader, launcher, key scanner, MCP server (pure Dart).
- `bin/` — `mcp`, `init`, `run`, `keys` executables.
- `templates/` — files `init` copies into an app (conf, testing guide, test-case README).
- `example/` — a small go_router app using the package by path. Invented data only.
- `test/` — library and CLI tests (the server test talks to it over stdio).

## Conventions
- Stay generic: no company, product, host or app id from any app that uses the package.
- Tools return only non-personal facts (route names, keys, booleans, codes). Never return app
  logs, add a log collector, or return on-screen text wholesale. `knownProblem` returns fixed
  messages only.
- Commits: short imperative subject. Personal GitHub account, personal email.

## Gotchas
- `MarionetteBinding.ensureInitialized` must run before the app's own start-up, or apps that
  start inside their own zone (crash reporters) create a second binding.
- iOS simulator permission changes end the running app, so grants happen before launch.
  Android grants need the app installed, so they run after.
- `fvm flutter` prints nothing outside an fvm project: use fvm only when the app has `.fvmrc`.
  Pick fvm versions numerically (`stable` must not win).
- Under `flutter test`, `Platform.resolvedExecutable` is the test engine, not `dart`.
- On Android, Back on the first page closes the app.
