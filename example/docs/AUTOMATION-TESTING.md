# Automation and AI testing

Set up with [flutter_ai_testing](https://pub.dev/packages/flutter_ai_testing). Two tools, each
for what it does best:

- **The `flutter-ai-testing` MCP server**: an AI agent starts the app on a device and drives it
  the way Playwright drives a browser. It reads the screen, taps and types **by test key**,
  scrolls, goes back, and checks which page is open after every step. Use it to run a test case
  from `test_cases/` on request.
- **[Maestro](https://maestro.mobile.dev)** (optional): repeatable YAML flows, and anything
  outside the Flutter app, such as OS permission dialogs.

## Layout

| Path | What it is |
|---|---|
| `test_cases/*.md` | Plain-language test cases. The source of truth for behaviour. |
| `marionette/main.dart` | Debug-only entrypoint that turns the agent tools on. Never imported by `lib/`. |
| `ai-testing.conf` | App id, permissions to grant, test-host check, key-index settings. |
| `docs/test-keys.md` | Every key, page by page. Generated, don't edit by hand. |
| `.mcp.json` | Registers the `flutter-ai-testing` MCP server (`dart run flutter_ai_testing:mcp`). |
| `.marionette/` | Connect addresses and run logs. Gitignored. |

## Running a test with an agent

1. Start an Android emulator or an iOS simulator.
2. Open the project in your agent (Claude Code, Codex, Cursor, Copilot) and approve the
   `flutter-ai-testing` server when asked.
3. Ask, for example: "run TC-LOGIN-001 on the Android emulator".

The agent calls `list_devices` and `start_app`, which builds and installs the app, grants the OS
permissions in `ai-testing.conf` (Marionette can't tap native dialogs), and connects. The first
build can take minutes. Several devices can run side by side: every tool takes a `device`.

To start the app yourself instead, run `dart run flutter_ai_testing:run <device-id>` in a
terminal (`r` / `R` / `q` work as usual) and ask the agent to `attach`.

### What the agent can do

`get_interactive_elements` (what's on screen, with keys and labels), `tap`, `enter_text`,
`scroll_to`, `swipe`, `long_press`, `press_back_button`, `take_screenshots`, `hot_restart`.
Each action's reply ends with `after: {...}`: the page the action led to, once the screen has
settled and loading has finished. `where_am_i` gives the same answer any time.

The app adds its own tools, called with `call_custom_extension` (`<ns>` is the namespace in
`marionette/main.dart`):

| Tool | Use it for |
|---|---|
| `<ns>.whereAmI` | What `where_am_i` returns: page stack by name, the `*_screen` keys on screen (bottom page first), open dialogs, loading, signed in, app facts. |
| `<ns>.setupSignedOut` | **Test setup, not a test step.** Ends the session and shows the start page. |
| `<ns>.uiOnlyOpenRoute` / `<ns>.uiOnlyOpenScreen` | **UI-only shortcuts.** Open a page directly. |

### Reaching a page: the normal way first

- **Normal test (the default).** Reach every page the way a user does, by tapping. The path to
  the page is part of the test. Check each step's `after:`.
- **UI-only check.** When someone asks only how one page looks, the agent may jump there with
  a `uiOnly…` tool. The report must say so, and a jump never counts as passing a flow test.

### Page map

"Check" is the key `where_am_i` lists in `visibleScreens` when the page is showing.

| Page | Check | Normal path | Needs | UI-only shortcut |
|---|---|---|---|---|
| Example: Login | `login_screen` | App start, no session | — | route `login` |

### Starting state for a case

| Precondition | How to get it |
|---|---|
| Signed out | `<ns>.setupSignedOut` |
| Signed in | Sign in through the login page with the test account (part of the test) |
| Fresh install | `stop_app`, clear the app's data (`adb shell pm clear <app id>`, or uninstall it from the simulator), then `start_app` again |

### Limits

- **Debug and profile builds only.** `runWithAiTesting` throws in release mode.
- **Inside the Flutter app only.** OS permission dialogs and the keyboard are native: the tools
  can't see or tap them, and screenshots show that area blank. Use Maestro for native UI.
- **The app must be in the foreground.** In the background it draws no frames, and calls time
  out after 45 s with a hint.
- **On Android, Back on the first page closes the app.** Use the page's own back buttons.
- **Logs are never shown to the agent**, on purpose: debug output can contain personal data.
- **Use a made-up test account.** Pass the password in the conversation for that run only, never
  in a repo file. Don't take screenshots of pages that show personal data unless asked.

## Repeatable flows with Maestro

```sh
maestro --device <device-id> test maestro/<flow>.yaml
```

Maestro reads the accessibility tree, so it matches **visible text**, not keys. Pass credentials
as environment variables (`-e TEST_EMAIL=...`), never in a file. Don't use the `maestro` MCP
cloud tools (`run_on_cloud` and similar): they upload the app and its screens.

## Keys

- Every page root gets a `<area>_<page>_screen` key; every control a test uses gets a key.
  Never key a widget by its text, and never put personal data in a key.
- After changing keys run `dart run flutter_ai_testing:keys check` and
  `dart run flutter_ai_testing:keys index`.

## Writing a new case

1. Add the case to `test_cases/<area>.md` with the next free ID.
2. Make sure every control it uses has a key (`docs/test-keys.md`). Add one if not.
3. Run it with the agent and check the result against the expected results.
4. If it should run repeatedly without an agent, add a Maestro flow for it.
