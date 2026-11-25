# flutter-ai-testing

An **MCP server** that lets any AI agent (Claude Code, Codex, Cursor, Copilot, or any MCP
client) test a Flutter app the way a person does, on Android and iOS: start the app on a
device, read the screen, tap and type by test key, confirm which page is open, and report.
Built on [Marionette](https://pub.dev/packages/marionette_mcp) for the app and
[Maestro](https://maestro.mobile.dev) for native UI.

## The MCP server

`mcp/server.py` (installed into apps as `scripts/ai-testing/mcp_server.py`). Python standard
library only. It runs one `marionette_mcp` per device behind the scenes.

| Tool | What it does |
|---|---|
| `list_devices` | Android and iOS devices, emulators and simulators. |
| `start_app(app_dir, device)` | Builds, installs, grants OS permissions, launches the Marionette entrypoint and connects. |
| `attach(app_dir, device)` | Connects to an app already started with `marionette-run.sh`. |
| `app_status`, `stop_app` | State of each app (starting, running, exited, a known problem). Never returns log text. |
| `where_am_i` | Page stack, `*_screen` keys on screen, open dialogs, loading, signed in, app facts. |
| `check_keys`, `key_index` | The key checks. |
| `tap`, `enter_text`, `scroll_to`, `swipe`, `press_back_button`, `get_interactive_elements`, `take_screenshots`, `hot_restart`, `call_custom_extension`, ... | Marionette's own tools, each with an optional `device`, so several devices can be driven side by side. `connect` and `get_logs` are not exposed. |

A call that gets no answer within 45 s (`AI_TESTING_CALL_TIMEOUT`) fails with a hint instead
of hanging: an app in the background draws no frames.

### Register it

In an app with the kit installed, the project's `.mcp.json` (added by `install.sh`) already
registers `python3 scripts/ai-testing/mcp_server.py`, which Claude Code picks up. For other
clients, or for every project on your machine, point them at the same file:

| Client | How |
|---|---|
| Claude Code (all projects) | `claude mcp add --scope user flutter-ai-testing -- python3 /path/to/flutter-ai-testing/mcp/server.py` |
| Codex | `~/.codex/config.toml`: `[mcp_servers.flutter-ai-testing]` `command = "python3"` `args = ["/path/to/mcp/server.py"]` |
| Cursor | `.cursor/mcp.json`: same shape as `.mcp.json` |
| VS Code / Copilot | `.vscode/mcp.json`: `{"servers": {"flutter-ai-testing": {"command": "python3", "args": ["scripts/ai-testing/mcp_server.py"]}}}` |

The server sends its usage rules as MCP `instructions` (normal path first, no personal data,
`where_am_i` after every step), so a client that shows them needs no extra prompt.

## What you get

| Piece | What it does |
|---|---|
| `lib/flutter_ai_testing.dart` | Agent tools registered in the app: `<ns>.whereAmI` (page stack, `*_screen` keys on screen, open dialogs, loading, signed in, app facts), `<ns>.setupSignedOut` (test setup), and `uiOnly…` shortcuts for checking one page's layout. |
| `scripts/marionette-run.sh` | Starts the app through its Marionette entrypoint, saves the connect address to `.marionette/<device>.uri`, grants OS permissions (Android after install, iOS simulator before launch), and refuses a compile-time host that isn't a test host. |
| `scripts/check_test_keys.py` | Fails on keys that look like contact data; warns on keys repeated in one file. |
| `scripts/gen_test_key_index.py` | Writes `docs/test-keys.md`: every key, page by page, with the widget, label and where it navigates. |
| `mcp/server.py` | The MCP server above. |
| `tools/marionette_cli.py` | Command-line Marionette client: `where`, a list of tool calls, `list`. |
| `tools/vmeval.py` | Reads one value from the running debug app (for diagnosing state the screen doesn't show). |
| `templates/` | Starting files: `ai-testing.conf`, Marionette entrypoint, app tools, widget config, MCP config, testing guide, test-case README. |
| `example/` | A small app with everything installed and filled in. |

## Install into an app

```sh
bash install.sh /path/to/app            # or --scripts-dir scripts/ai --marionette-dir marionette
cd /path/to/app
flutter pub add --dev 'marionette_flutter:^0.7.0'
dart pub global activate marionette_mcp 0.7.0   # once per machine, same version
```

Then:

1. Fill in `ai-testing.conf` (app id, test host check, permissions, key settings).
2. Fill in `marionette/main.dart` (the app's start-up function) and `marionette/app_tools.dart`
   (namespace, route stack, sign-in check, sign-out, shortcut routes and screens).
3. List the app's custom controls in `marionette/marionette_config.dart`.
4. Key every page root (`<area>_<page>_screen`) and every control a test uses.
5. `python3 scripts/ai-testing/check_test_keys.py && python3 scripts/ai-testing/gen_test_key_index.py`
6. Write the page map in `docs/AUTOMATION-TESTING.md` and the cases in `test_cases/`.
7. `bash scripts/ai-testing/marionette-run.sh <device-id>` and ask the agent to run a case.

The app gets **copies**, not a package dependency, so its CI and teammates never need access
to this repository. `install.sh` always refreshes the copies (`marionette/ai_testing.dart`,
`scripts/ai-testing/`) and never overwrites the files the app filled in. Don't edit the copies
in the app: change them here, then run `install.sh` again.

## Rules the tools are built around

- **The normal path first.** A test reaches every page by tapping, like a user. `uiOnly…`
  shortcuts are for checking one page's layout only, and a report must say when one was used.
- **No personal data.** Tools return route names, keys, booleans and codes only. Marionette log
  collection stays off (debug output often has personal data). Keys must not contain personal
  data (`check_test_keys.py` fails on contact-like keys). Use made-up test accounts, passed in the
  conversation, never written to a file.
- **Test hosts only.** `DEFINE_MUST_CONTAIN` makes the launch script refuse a non-test host.
- **Don't use Maestro's cloud tools**: they upload the app and its screens.

## Develop

```sh
flutter pub get && flutter analyze && flutter test       # the library
cd example && flutter analyze                            # the example
bash -n install.sh scripts/marionette-run.sh             # script syntax
```

To try it live: `cd example && bash scripts/ai-testing/marionette-run.sh <device-id>`, then
`python3 scripts/ai-testing/marionette_cli.py <device-id> where`.

Version: see `VERSION`. Bump it when the installed copies change.
