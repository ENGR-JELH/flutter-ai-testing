# Automation and AI testing

Set up with [flutter-ai-testing](https://github.com/ENGR-JELH/flutter-ai-testing). Two tools,
each for what it does best:

- **[Marionette](https://pub.dev/packages/marionette_mcp)**: an AI agent drives the running app the
  way Playwright drives a browser. It reads the screen, taps and types **by test key**, scrolls,
  takes screenshots and goes back. Use it to run a test case from `test_cases/` on request.
- **[Maestro](https://maestro.mobile.dev)**: repeatable YAML flows, and anything outside the
  Flutter app, such as OS permission dialogs.

## Layout

| Path | What it is |
|---|---|
| `test_cases/*.md` | Plain-language test cases. The source of truth for behaviour. |
| `marionette/main.dart` | Debug-only entrypoint that turns on Marionette. Never imported by `lib/`. |
| `marionette/marionette_config.dart` | Teaches Marionette the app's own widgets. |
| `marionette/app_tools.dart` | This app's settings for the agent tools (routes, sign-in, shortcuts). |
| `marionette/ai_testing.dart` | The agent tools. Installed copy: don't edit, re-run `install.sh`. |
| `scripts/ai-testing/` | Launch script and key checks. Installed copies. |
| `ai-testing.conf` | Settings for the scripts (app id, permissions, key index). |
| `maestro/*.yaml` | Maestro flows, one per test case. |
| `docs/test-keys.md` | Every key, page by page. Generated, don't edit by hand. |
| `.mcp.json` | Registers the `marionette` and `maestro` MCP servers for Claude Code. |

## AI-driven testing with Marionette

### One-time setup

```sh
dart pub global activate marionette_mcp 0.7.0   # must match marionette_flutter in pubspec.yaml
```

### Each session

1. Start an Android emulator or an iOS simulator.
2. Run the app through the Marionette entrypoint:
   ```sh
   bash scripts/ai-testing/marionette-run.sh <device-id>     # ids: flutter devices
   ```
   It prints `MARIONETTE_URI=ws://127.0.0.1:<port>/<token>/ws` and saves that address to
   `.marionette/<device-id>.uri` (gitignored), so an agent can connect without asking you.
   Run one per device to test Android and iOS side by side.

   It grants the OS permissions listed in `ai-testing.conf`, because Marionette can't tap
   native dialogs. The iOS simulator can't pre-grant notifications: tap "Allow" with Maestro
   the first time. Use `MARIONETTE_GRANT=0` for a case that tests the permission prompts.
3. In Claude Code, approve the `marionette` server when asked, then say for example
   "run TC-LOGIN-001 on the Android emulator".

### What the agent can do

`get_interactive_elements` (what's on screen, with keys and labels), `tap`, `enter_text`,
`scroll_to`, `swipe`, `long_press`, `press_back_button`, `take_screenshots`, `hot_restart`.
Target a control by its key from `docs/test-keys.md`, or by its visible text.

The app adds its own tools, called with `call_custom_extension` (`<ns>` is the namespace in
`marionette/app_tools.dart`):

| Tool | Use it for |
|---|---|
| `<ns>.whereAmI` | Read-only, any time. The page stack by name, the `*_screen` keys on screen (bottom page first), open dialogs by type, whether a spinner shows, whether a user is signed in, and app facts. Use it after every step, and poll it while `loading` is true. |
| `<ns>.setupSignedOut` | **Test setup, not a test step.** Ends the session and shows the start page. |
| `<ns>.uiOnlyOpenRoute` / `<ns>.uiOnlyOpenScreen` | **UI-only shortcuts.** Open a page directly. |

### Reaching a page: the normal way first

- **Normal test (the default).** Reach every page the way a user does, by tapping. The path to
  the page is part of the test. Confirm each step with `whereAmI`.
- **UI-only check.** When someone asks only how one page looks, the agent may jump there with
  a `uiOnly…` tool. The report must say so, and a jump never counts as passing a flow test.

### Page map

"Check" is the key `whereAmI` lists in `visibleScreens` when the page is showing.

| Page | Check | Normal path | Needs | UI-only shortcut |
|---|---|---|---|---|
| Example: Login | `login_screen` | App start, no session | — | route `login` |

### Starting state for a case

| Precondition | How to get it |
|---|---|
| Signed out | `<ns>.setupSignedOut` |
| Signed in | Sign in through the login page with the test account (part of the test) |
| Fresh install | Stop the app, clear its data (`adb shell pm clear <app id>`, or uninstall it from the simulator), then start `marionette-run.sh` again |

### Limits

- **Debug and profile builds only.** `marionette/main.dart` throws in release mode.
- **Inside the Flutter app only.** OS permission dialogs and the keyboard are native: Marionette
  can't see or tap them, and its screenshots show that area blank. Use Maestro for native UI,
  and `xcrun simctl io <udid> screenshot <file>` or `adb exec-out screencap -p` for a full picture.
- **On Android, Back on the first page closes the app.** Use the page's own back buttons.
- **Logs are not collected**, on purpose: debug output can contain personal data.
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
- After changing keys run `python3 scripts/ai-testing/check_test_keys.py` and
  `python3 scripts/ai-testing/gen_test_key_index.py`.

## Writing a new case

1. Add the case to `test_cases/<area>.md` with the next free ID.
2. Make sure every control it uses has a key (`docs/test-keys.md`). Add one if not.
3. Run it with Marionette and check the result against the expected results.
4. If it should run repeatedly without an agent, add a Maestro flow for it.
