# flutter_ai_testing: developer guide

This guide shows how to make a Flutter app testable by an AI agent (Claude Code, Codex, Cursor,
Copilot, or any MCP client), and how to run tests with it on Android and iOS.

**Contents**

1. [How it works](#1-how-it-works)
2. [Requirements](#2-requirements)
3. [Quick start (5 minutes)](#3-quick-start-5-minutes)
4. [What `init` creates](#4-what-init-creates)
5. [Add test keys](#5-add-test-keys)
6. [Configure the app tools](#6-configure-the-app-tools)
7. [Settings file: `ai-testing.conf`](#7-settings-file-ai-testingconf)
8. [Run a test with an agent](#8-run-a-test-with-an-agent)
9. [Write test cases](#9-write-test-cases)
10. [Tool reference](#10-tool-reference)
11. [Privacy and safety rules](#11-privacy-and-safety-rules)
12. [Troubleshooting](#12-troubleshooting)
13. [FAQ](#13-faq)

---

## 1. How it works

```
  You: "run TC-LOGIN-001 on the Android emulator"
   │
   ▼
┌──────────────────────┐   MCP (stdio)   ┌───────────────────────────────┐
│ AI agent             │ ──────────────▶ │ flutter_ai_testing:mcp        │
│ Claude Code, Codex,  │ ◀────────────── │ (runs on your machine)        │
│ Cursor, Copilot ...  │   results +     │  • flutter run on the device  │
└──────────────────────┘   "after: {..}" │  • grants OS permissions      │
                                         │  • one marionette_mcp/device  │
                                         └──────────────┬────────────────┘
                                                        │ Dart VM service
                                                        ▼
                                         ┌───────────────────────────────┐
                                         │ Your app, debug build         │
                                         │ started from                  │
                                         │ marionette/main.dart          │
                                         │  • Marionette: tap, type,     │
                                         │    scroll, read the screen    │
                                         │  • <ns>.whereAmI and setup    │
                                         │    tools                      │
                                         └───────────────────────────────┘
```

- Your app keeps its normal `lib/main.dart`. A second, **debug-only** entrypoint,
  `marionette/main.dart`, wraps it and turns the testing tools on. Nothing in `lib/` changes,
  and release builds don't contain the tools.
- The agent talks to the **MCP server**, which builds and starts the app on a device, connects,
  and passes the agent's taps and text to it.
- After every action the server waits for the screen to settle and for loading to finish, then
  reports **where the action led** (page, dialogs, loading, signed in). The agent checks that
  before its next step, the way a person looks at the screen.

---

## 2. Requirements

| Need | Notes |
|---|---|
| Flutter 3.32 or newer, Dart 3.8 or newer | `flutter` on `PATH`, or fvm (see `FLUTTER_VERSION` below). |
| An Android emulator / device, or an iOS simulator / device | iOS needs macOS and Xcode. |
| An MCP-capable agent | Claude Code, Codex, Cursor, VS Code Copilot, and others. |
| `adb` (Android) | From the Android SDK; found on `PATH` or in `$ANDROID_HOME`. |

No Python, and no global installs: everything runs from the package.

---

## 3. Quick start (5 minutes)

```sh
# 1. In your app's folder
flutter pub add dev:flutter_ai_testing

# 2. Create the entrypoint, settings and MCP registration
dart run flutter_ai_testing:init

# 3. Start an emulator or simulator
flutter emulators --launch <emulator-id>
```

4. **Restart your agent** in the app's folder, and approve the `flutter-ai-testing` server when
   it asks.
5. Ask it:

   > List the devices and start the app on the Android emulator. Then tell me which page is open.

The first build takes a few minutes, like any first `flutter run`. After that, try:

> Tap "Sign in" and tell me where it leads.

That works with no further setup, using visible text. For tests that keep working when text
changes, add keys ([section 5](#5-add-test-keys)).

---

## 4. What `init` creates

`init` only creates files that don't exist yet. Run it again any time; it never overwrites
your changes and never touches `lib/`.

| File | What it is | Commit it? |
|---|---|---|
| `marionette/main.dart` | Debug-only entrypoint: `runWithAiTesting(app.main)`. | Yes |
| `ai-testing.conf` | App id, OS permissions to grant, test-host check, key settings. | Yes |
| `.mcp.json` | Registers the server: `dart run flutter_ai_testing:mcp`. Existing servers are kept. | Yes |
| `docs/AUTOMATION-TESTING.md` | Your app's testing guide, with a page map to fill in. | Yes |
| `test_cases/README.md` | The test-case format. | Yes |
| `.gitignore` line `.marionette/` | Run files: connect addresses and app logs. | Never commit `.marionette/` |

The generated entrypoint:

```dart
import 'package:flutter_ai_testing/flutter_ai_testing.dart';
import 'package:my_app/main.dart' as app;

void main() => runWithAiTesting(
      app.main,
      config: const AiTestingConfig(namespace: 'my_app'),
    );
```

`app.main` is your whole `main()`, so config loading, Firebase and anything else in it still
runs. If your `main` takes arguments or lives elsewhere, point the import at the right function.

---

## 5. Add test keys

Keys are what make tests reliable. They are to this package what `data-testid` is to Playwright.

### Page keys (required for page checks)

Give the root widget of every page a key that ends in `_screen`:

```dart
return Scaffold(
  key: const ValueKey('login_screen'),
  ...
);
```

`where_am_i` lists these keys in `visibleScreens`, so the agent can confirm "I'm on the login
page" without guessing from text.

### Control keys

Key every control a test touches:

```dart
TextField(key: const ValueKey('login_email_field'), ...)
ElevatedButton(key: const ValueKey('login_sign_in_button'), ...)
ListTile(key: ValueKey('home_item_$index'), ...)   // a list: add the index or a safe id
```

### Naming

- Pattern: `<area>_<page>_<element>`, lower case with underscores: `account_settings_save_button`.
- Pages end in `_screen`; fields in `_field`; buttons in `_button`; tabs `nav_tab_<name>`.
- **Never** build a key from visible text, a person's name, an email or phone number. Use an
  index or an internal id.
- Keys may live in a constants class (`TestKeys.loginScreen`). Tell the key tools about it with
  `KEYS_CLASS` and `KEYS_CONSTANTS` in `ai-testing.conf`.

### Check and index

```sh
dart run flutter_ai_testing:keys check    # fails on keys that look like contact data, warns on duplicates
dart run flutter_ai_testing:keys index    # writes docs/test-keys.md: every key, page by page
```

`docs/test-keys.md` lists each key with the widget it is on, the label it shows and where it
navigates. The agent reads it to find the right key. Regenerate it after changing keys.

---

## 6. Configure the app tools

With no config the tools already report the `_screen` keys on screen, open dialogs and whether
the app is loading. A config adds page names, sign-in state and shortcuts. All fields are
callbacks, so it works with any router and any state management.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_ai_testing/flutter_ai_testing.dart';
import 'package:my_app/main.dart' as app;

void main() => runWithAiTesting(
      app.main,
      config: AiTestingConfig(
        namespace: 'myapp',

        // Page names in where_am_i (go_router helper; see below for other routers)
        routeStack: () => GoRouterTools.stack(app.router),
        location: () => GoRouterTools.location(app.router),

        // Sign-in state, and the setupSignedOut tool
        isSignedIn: () => app.session.isSignedIn,
        signOut: () async {
          await app.session.signOut();
          app.router.goNamed('login');
        },

        // Extra facts, non-personal only
        appState: () => {'tab': app.currentTabName, 'darkMode': app.isDark},

        // UI-only shortcuts (see "Normal path vs UI-only" in section 8)
        uiOnlyRoutes: const ['login', 'settings', 'help'],
        openRoute: (name, {required replace}) =>
            GoRouterTools.open(app.router, name, replace: replace),
        uiOnlyScreens: {
          'editProfile': () => app.navigatorKey.currentState!
              .push(MaterialPageRoute(builder: (_) => const app.EditProfilePage())),
        },
      ),
    );
```

| Field | What it does | Default |
|---|---|---|
| `namespace` | Prefix of the app tools: `myapp.whereAmI`, `myapp.setupSignedOut`, ... | required |
| `routeStack` | Open pages by name, bottom first. | empty (pages still show through `_screen` keys) |
| `location` | Current path. | not reported |
| `isSignedIn` | Whether a user is signed in. | not reported |
| `signOut` | Ends the session and shows the start page. Turns on `setupSignedOut`. | tool off |
| `appState` | Extra facts merged into `where_am_i`. | none |
| `uiOnlyRoutes` + `openRoute` | Routes `uiOnlyOpenRoute` may open. | tool off |
| `uiOnlyScreens` | Pages without a route that `uiOnlyOpenScreen` may push. | tool off |
| `screensNeedSignIn` | `uiOnlyOpenScreen` refuses while signed out. | `true` |
| `screenKeySuffix` | Suffix that marks a page key. | `_screen` |
| `loadingWidgetTypes` | Widget types that mean "loading". Add your own spinner here. | stock spinners |
| `maxSettle` | Longest wait for animations before answering. | 2 s |

### Routers other than go_router

Give `routeStack` any function that returns page names. With Navigator 1.0, a small
`NavigatorObserver` that records route names in a list is enough:

```dart
class RouteNames extends NavigatorObserver {
  final names = <String>[];
  @override
  void didPush(Route r, Route? p) => names.add(r.settings.name ?? r.runtimeType.toString());
  @override
  void didPop(Route r, Route? p) => names.removeLast();
}
```

Add the observer to your `MaterialApp` in debug builds and pass `routeStack: () => observer.names`.

`GoRouterTools.stack` names a pushed page by `extra['routeName']` when the page is pushed with a
map `extra` that has one; otherwise by its route name or path.

### Custom buttons and fields

Marionette recognises Flutter's own buttons, fields, switches and list tiles. If your app draws
its own (for example an `AppButton` built from `GestureDetector`), list them, or the agent won't
see them:

```dart
runWithAiTesting(
  app.main,
  config: ...,
  marionette: MarionetteConfiguration(
    isInteractiveElement: (element) => switch (element.widget) {
      AppButton() || AppTextField() => true,
      _ => false,
    },
    extractText: (element) => switch (element.widget) {
      AppButton(:final label) => label,
      _ => null,
    },
  ),
);
```

Don't add a log collector to `MarionetteConfiguration`: debug output often contains personal
data, and the agent would read it.

---

## 7. Settings file: `ai-testing.conf`

Plain `KEY=value` lines; `#` starts a comment. It is read, never executed.

| Key | What it does | Example |
|---|---|---|
| `APP_ID` | Android application id / iOS bundle id. Used to grant permissions. | `com.acme.shop` |
| `TARGET` | The entrypoint to run. | `marionette/main.dart` |
| `ANDROID_PERMISSIONS` | Granted after install (`pm grant`), space-separated. | `ACCESS_FINE_LOCATION POST_NOTIFICATIONS` |
| `IOS_PERMISSIONS` | Granted on the simulator before launch (`simctl privacy`). | `location photos camera` |
| `FLUTTER_VERSION` | Use `~/fvm/versions/<version>` when the app has no `.fvmrc`. | `3.32.0` |
| `DEFINE_NAME` | A `--dart-define` the test build needs. | `API_BASE_URL` |
| `DEFINE_DEFAULT` | Its value, unless the same-named environment variable is set. | `https://test.acme.dev` |
| `DEFINE_MUST_CONTAIN` | Refuse to start unless the value contains this. Stops tests against production. | `test` |
| `URI_DIR` | Where run files go. | `.marionette` |
| `KEYS_LIB` | Folder the key tools scan. | `lib` |
| `KEYS_INDEX` | Where the key index is written. | `docs/test-keys.md` |
| `KEYS_CLASS`, `KEYS_CONSTANTS` | Key constants class, and its file. | `TestKeys`, `lib/shared/test_keys.dart` |
| `KEYS_DYNAMIC` | How to show a key built by a method (repeatable). | `navTab=nav_tab_<tab>` |
| `KEYS_TAB_SWITCH` | Method that switches tabs, so the index says "switches tab". | `changeTab` |
| `KEYS_NOTE` | Extra line for the index header (repeatable). | — |

Flutter is chosen in this order: `FLUTTER_BIN` environment variable, `fvm flutter` when the app
has `.fvmrc`, `FLUTTER_VERSION`, `flutter` on `PATH`, then the newest fvm version.

---

## 8. Run a test with an agent

### Typical session

1. Start one or more emulators / simulators.
2. Open your agent in the app folder.
3. Ask in plain words. For example:

   > Run TC-LOGIN-001 from test_cases/login.md on the Android emulator. Use the test account
   > test.user@example.com / its password is in my message, don't save it. Report each step.

   > On the iPhone simulator, open Settings the normal way and check the Save button is
   > disabled until a field changes.

   > UI-only check: open the Help page directly and tell me if anything overflows.

The agent will call `list_devices`, `start_app`, then actions such as `tap` and `enter_text`,
and check each reply's `after:` line. A reply looks like:

```
Tapped element matching: {key: login_sign_in_button}
after: {"location":"/home","stack":["home"],"visibleScreens":["home_screen"],
        "dialogs":[],"loading":false,"signedIn":true}
```

### Normal path vs UI-only

| | Normal test (default) | UI-only check |
|---|---|---|
| How the agent reaches the page | Taps through the app, like a user | Jumps there with `<ns>.uiOnlyOpenRoute` / `uiOnlyOpenScreen` |
| What it proves | The flow works | How one page looks |
| When | Every test case | Only when you ask for a layout check |
| Report | Normal | Must say a shortcut was used |

### Start the app yourself, then let the agent attach

Useful when you want to watch the build output or hot reload by hand:

```sh
dart run flutter_ai_testing:run emulator-5554
```

`r` (hot reload), `R` (hot restart) and `q` (quit) work as usual. Then ask the agent to
`attach` to `emulator-5554`.

### Several devices at once

Start the app on each device (`start_app` per device). Every action takes a `device` argument,
so one agent can run the same case on Android and iOS side by side. With one app running,
`device` can be left out.

### Starting state

| Precondition | How |
|---|---|
| Signed out | `<ns>.setupSignedOut` (test setup, not a test step) |
| Signed in | Sign in through the login page with the test account, as part of the test |
| Fresh install | `stop_app`, clear app data (`adb shell pm clear <app id>`, or uninstall from the simulator), `start_app` |

---

## 9. Write test cases

Keep cases as Markdown in `test_cases/<area>.md`. Describe what a user sees and does; name
controls by key.

```markdown
## TC-LOGIN-001: Sign in with a valid account

**Preconditions:** signed out (`setupSignedOut`). Test account from the tester.

**Steps**
1. On `login_screen`, enter the email in `login_email_field`.
2. Enter the password in `login_password_field`.
3. Tap `login_sign_in_button`.

**Expected**
- `home_screen` shows, `signedIn` is true, no dialog is open.
```

Rules: stable IDs (`TC-<AREA>-<NNN>`, never reused), made-up data only, and add a key to the app
before writing a step that needs one. Keep the page map in `docs/AUTOMATION-TESTING.md` up to
date: page, its `_screen` key, the normal path to reach it, and its shortcut if any.

---

## 10. Tool reference

### Server tools

| Tool | Arguments | What it does |
|---|---|---|
| `list_devices` | — | Android and iOS devices that can run the app. |
| `start_app` | `device`, `app_dir`?, `wait_seconds`? (300), `flutter_args`? | Builds, installs, grants permissions, launches and connects. Calling it again on the same device just waits. |
| `attach` | `device`, `app_dir`? | Connects to an app started with `flutter_ai_testing:run`. |
| `app_status` | — | Each app's state: starting, running, exited, and a known problem if any. |
| `stop_app` | `device`? | Stops the app. |
| `where_am_i` | `device`? | Page stack, `_screen` keys on screen, dialogs, loading, signed in, app facts. |
| `check_keys`, `key_index` | `app_dir`? | Same as the `keys` command. |

`app_dir` defaults to the folder the agent was started in.

### Marionette tools (passed through)

`get_interactive_elements`, `tap`, `double_tap`, `long_press`, `secondary_tap`, `enter_text`,
`scroll_to`, `swipe`, `pinch_zoom`, `press_back_button`, `press_key`, `take_screenshots`,
`set_device_config`, `hot_reload`, `hot_restart`, `list_custom_extensions`,
`call_custom_extension`. Each takes an optional `device`. Target a control by `key` (best) or by
visible `text`.

### App tools (through `call_custom_extension`)

| Extension | Arguments | Use |
|---|---|---|
| `<ns>.whereAmI` | — | What `where_am_i` returns. |
| `<ns>.setupSignedOut` | — | Test setup: end the session, show the start page. Needs `signOut`. |
| `<ns>.uiOnlyOpenRoute` | `name`, `mode` (`push` / `go`) | UI-only: open a route in `uiOnlyRoutes`. |
| `<ns>.uiOnlyOpenScreen` | `screen` | UI-only: push a page in `uiOnlyScreens`. |

### Commands

```sh
dart run flutter_ai_testing:init               # set up an app
dart run flutter_ai_testing:mcp                # the MCP server (your agent starts it)
dart run flutter_ai_testing:run <device-id>    # start the app yourself
dart run flutter_ai_testing:keys check         # key check
dart run flutter_ai_testing:keys index         # key index
```

Environment variables: `AI_TESTING_CALL_TIMEOUT` (seconds per call, 45),
`AI_TESTING_LOADING_WAIT` (seconds to wait for loading after an action, 15),
`AI_TESTING_APP_DIR` (default `app_dir`), `MARIONETTE_GRANT=0` (don't grant permissions, to test
the permission prompts), `FLUTTER_BIN`.

### Connecting other agents

`init` writes `.mcp.json`, which Claude Code reads. Cursor uses the same shape in
`.cursor/mcp.json`.

| Client | Setting |
|---|---|
| Codex | `~/.codex/config.toml`: `[mcp_servers.flutter-ai-testing]`, `command = "dart"`, `args = ["run", "flutter_ai_testing:mcp"]` |
| VS Code / Copilot | `.vscode/mcp.json`: `{"servers": {"flutter-ai-testing": {"command": "dart", "args": ["run", "flutter_ai_testing:mcp"]}}}` |

Start the client in the app folder, so `dart run` finds the package.

---

## 11. Privacy and safety rules

These are built into the tools and repeated to the agent in the server's instructions.

- **No personal data out of the app.** Tools return route names, keys, booleans and codes.
  App logs go to `.marionette/<device>.log` and are never returned; Marionette's `get_logs` is
  hidden. A failed start reports a fixed message ("Android build failed..."), never log text.
- **Your `appState` and keys must follow the same rule**: no names, emails, phone numbers or
  addresses. `keys check` fails on keys that look like contact data.
- **Made-up test accounts only.** Give the password in the conversation for that run; never put
  it in a repo file or a test case.
- **Test servers only.** Use `DEFINE_MUST_CONTAIN` so a test build can't point at production.
- **Debug and profile builds only.** `runWithAiTesting` throws in release mode, and nothing in
  `lib/` imports it.
- **Screenshots** of pages with personal data only when you ask for them.

---

## 12. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Agent doesn't list the `flutter-ai-testing` tools | Restart the agent in the app folder and approve the server. Check `.mcp.json` has the entry, and that `flutter pub get` ran. |
| `start_app` says "no ai-testing.conf" | Run `dart run flutter_ai_testing:init` in the app folder. |
| `start_app` returns "starting" | First builds are slow. Call `app_status` until "running". |
| `problem: Android build failed` / `iOS build failed` | Run `dart run flutter_ai_testing:run <device>` in a terminal to see the full error. |
| "no answer from the app within 45s" | The app is in the background, behind another app, or paused at a breakpoint. Bring it to the front and retry. |
| "Element matching {key: ...} not found" | The control isn't on screen yet (check `after:`), it's under an open dialog, it needs `scroll_to`, or the key is wrong (see `docs/test-keys.md`). |
| A custom button is invisible to the agent | List it in `MarionetteConfiguration.isInteractiveElement` ([section 6](#custom-buttons-and-fields)). |
| `visibleScreens` is empty | The page root has no `_screen` key. |
| `stack` is empty | No `routeStack` in the config. |
| "refusing: X must contain 'test'" | The `--dart-define` value failed the safety check. Set the right test value. |
| Permission dialog blocks the app | Add the permission to `ANDROID_PERMISSIONS` / `IOS_PERMISSIONS`. iOS notifications can't be pre-granted on the simulator; tap Allow once by hand. |
| App closed after Back on Android | Back on the first page closes the app. Use the page's own back buttons; `start_app` again. |
| "a second binding" error at start | Your app creates the binding itself before `runWithAiTesting` runs. Keep `runWithAiTesting` as the very first call in `marionette/main.dart`. |
| `fvm` / wrong Flutter version | Add `.fvmrc`, set `FLUTTER_VERSION` in `ai-testing.conf`, or set `FLUTTER_BIN`. |

---

## 13. FAQ

**Does this change my app?**
No. It adds a dev dependency and files outside `lib/`. Your release build is the same as before.

**Is it like Playwright?**
For the agent, yes: it drives the real app, targets controls by key, and checks state after each
step. The difference is that an AI agent runs the steps from a plain-language test case, instead
of a test script.

**Can it run in CI?**
The tools need a running device and an agent, so they are meant for local and on-request testing.
Keep your unit and widget tests for CI.

**Can it tap OS dialogs, the keyboard, or other apps?**
No. It only sees the Flutter UI. Permissions are granted up front; for other native UI use a
tool such as Maestro.

**Does it work on a physical device?**
Yes. Pass the device id from `list_devices`. OS permissions aren't granted automatically on
physical devices, so grant them by hand.

**Which agents work?**
Any MCP client. The server sends its own usage rules, so no extra prompt is needed.

**How do I update it?**
`flutter pub upgrade flutter_ai_testing`. `init` never overwrites your files, so run it again only
to pick up files added in a new version.
