# flutter_ai_testing

Let any AI agent (Claude Code, Codex, Cursor, Copilot, or any MCP client) test your Flutter app
the way a person does, on Android and iOS: start the app on a device, read the screen, tap and
type by test key, confirm which page is open after every step, and report.

One dev dependency, no changes to your app's code: the tools live in a debug-only entrypoint
next to `lib/`. Built on [Marionette](https://pub.dev/packages/marionette_flutter).

**Full guide:** [doc/guide.md](doc/guide.md): setup, keys, configuration, running tests,
writing test cases, tool reference and troubleshooting.

## Set up

```sh
flutter pub add dev:flutter_ai_testing
dart run flutter_ai_testing:init
```

`init` creates only what is missing and never touches `lib/`:

| File | What it is |
|---|---|
| `marionette/main.dart` | Debug-only entrypoint: `runWithAiTesting(app.main)`. |
| `ai-testing.conf` | App id (read from Android), OS permissions to grant, optional test-host check, key settings. |
| `.mcp.json` | Registers the server: `dart run flutter_ai_testing:mcp`. |
| `docs/AUTOMATION-TESTING.md`, `test_cases/README.md` | A testing guide and test-case format to fill in. |
| `.gitignore` | Adds `.marionette/` (connect addresses and run logs). |

Then give every page root a key ending in `_screen` (`ValueKey('login_screen')`) and key the
controls tests use. Restart your agent and ask it to "list devices and start the app".

## The MCP server

| Tool | What it does |
|---|---|
| `list_devices` | Android and iOS devices, emulators and simulators. |
| `start_app(device)` | Builds, installs, grants OS permissions, launches `marionette/main.dart` and connects. |
| `attach(device)` | Connects to an app you started with `dart run flutter_ai_testing:run <device>`. |
| `app_status`, `stop_app` | State of each app (starting, running, exited, a known problem). Never returns log text. |
| `where_am_i` | Page stack, `*_screen` keys on screen, open dialogs, loading, signed in, app facts. |
| `check_keys`, `key_index` | Key checks and the key index (`docs/test-keys.md`). |
| `tap`, `enter_text`, `scroll_to`, `swipe`, `press_back_button`, `get_interactive_elements`, `take_screenshots`, `hot_restart`, `call_custom_extension`, ... | Marionette's tools, each with an optional `device`, so several devices run side by side. |

Every action's reply ends with `after: {...}`: where the action led once the screen settled and
loading finished (up to 15 s, `AI_TESTING_LOADING_WAIT`). A call that gets no answer in 45 s
(`AI_TESTING_CALL_TIMEOUT`) fails with a hint instead of hanging. The server sends its rules
as MCP `instructions` (normal path first, no personal data, check every step).

### Other clients

`init` writes `.mcp.json`, which Claude Code and Cursor (`.cursor/mcp.json`, same shape) read.

| Client | How |
|---|---|
| Codex | `~/.codex/config.toml`: `[mcp_servers.flutter-ai-testing]` `command = "dart"` `args = ["run", "flutter_ai_testing:mcp"]` (run from the app folder) |
| VS Code / Copilot | `.vscode/mcp.json`: `{"servers": {"flutter-ai-testing": {"command": "dart", "args": ["run", "flutter_ai_testing:mcp"]}}}` |

## Configure

Without a config the tools already report the `*_screen` keys on screen, dialogs and loading.
Add a config for page names, sign-in state and shortcuts:

```dart
import 'package:flutter_ai_testing/flutter_ai_testing.dart';
import 'package:my_app/main.dart' as app;

void main() => runWithAiTesting(
      app.main,
      config: AiTestingConfig(
        namespace: 'myapp',
        routeStack: () => GoRouterTools.stack(app.router),     // go_router; any router works
        location: () => GoRouterTools.location(app.router),
        isSignedIn: () => app.session.isSignedIn,
        appState: () => {'tab': app.currentTab},                // non-personal facts only
        signOut: () => app.session.signOut(),                   // enables setupSignedOut
        uiOnlyRoutes: const ['login', 'settings'],
        openRoute: (name, {required replace}) =>
            GoRouterTools.open(app.router, name, replace: replace),
      ),
      // Teach Marionette custom buttons and fields it doesn't recognise:
      marionette: MarionetteConfiguration(
        isInteractiveElement: (e) => e.widget is AppButton,
      ),
    );
```

| Setting | For |
|---|---|
| `namespace` | Tool prefix: `myapp.whereAmI`, `myapp.setupSignedOut`, `myapp.uiOnlyOpenRoute`, `myapp.uiOnlyOpenScreen`. |
| `routeStack`, `location` | Page names in `where_am_i`. |
| `isSignedIn`, `signOut` | Signed-in state, and the `setupSignedOut` test-setup tool. |
| `appState` | Extra facts, such as the selected tab. |
| `uiOnlyRoutes` + `openRoute`, `uiOnlyScreens` | UI-only shortcuts to open a page directly. |
| `loadingWidgetTypes` | Widget types that mean "still loading" (default: the stock spinners). |

`ai-testing.conf` settings: `APP_ID`, `TARGET`, `ANDROID_PERMISSIONS`, `IOS_PERMISSIONS`,
`FLUTTER_VERSION`, `DEFINE_NAME` / `DEFINE_DEFAULT` / `DEFINE_MUST_CONTAIN` (a `--dart-define`
with a safety check, so tests can't run against a production host), and the `KEYS_*` settings
for the key index. The template written by `init` explains each one.

## Commands

```sh
dart run flutter_ai_testing:init                  # set up an app
dart run flutter_ai_testing:mcp                   # the MCP server (your agent starts it)
dart run flutter_ai_testing:run <device-id>       # start the app yourself; then `attach`
dart run flutter_ai_testing:keys check            # fail on keys that look like contact data
dart run flutter_ai_testing:keys index            # write docs/test-keys.md
```

## Rules the tools are built around

- **The normal path first.** A test reaches every page by tapping, like a user. `uiOnly…`
  shortcuts are for checking one page's layout only, and a report must say when one was used.
- **No personal data.** Tools return route names, keys, booleans and codes. App logs go to
  `.marionette/<device>.log` and are never returned; Marionette's `get_logs` is not exposed.
  Use made-up test accounts, passed in the conversation, never written to a file.
- **Debug and profile builds only.** `runWithAiTesting` throws in release mode, and nothing in
  `lib/` imports it, so release builds don't contain it.

## Limits

- Only the Flutter UI: OS permission dialogs and the keyboard are native. Permissions listed in
  `ai-testing.conf` are granted for you (Android after install, iOS simulator before launch).
  For other native UI use a tool such as [Maestro](https://maestro.mobile.dev).
- The app must be in the foreground: in the background it draws no frames.
- On Android, Back on the first page closes the app.

## Develop

```sh
flutter pub get && flutter analyze && flutter test
cd example && flutter pub get && flutter analyze marionette lib
```

`example/` depends on the package by path. To test the server for real, open `example/` in an
MCP client with an emulator running and drive it (`start_app`, taps, `where_am_i`, `stop_app`).
