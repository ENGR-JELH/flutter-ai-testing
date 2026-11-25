# flutter-ai-testing example

A small app with flutter-ai-testing installed and filled in: a made-up sign-in, a list of three
invented items, a details page and a help page. Every page root and control has a key. Use it to
try the kit, and to test the kit after changing it.

| File | What it shows |
|---|---|
| `ai-testing.conf` | Launch and key settings |
| `marionette/main.dart` | The Marionette entrypoint |
| `marionette/app_tools.dart` | The app's settings for the agent tools (go_router stack, sign-in, sign-out, shortcuts) |
| `docs/test-keys.md` | The generated key index |

## Try it

```sh
flutter pub get
python3 scripts/ai-testing/mcp_server.py      # or let an MCP client start it from .mcp.json
```

Then, from the MCP client: `list_devices`, `start_app(device: "<id>")`, and for example
`enter_text(key: "login_name_field", input: "Test User")`, `tap(key: "login_sign_in_button")`,
`tap(key: "home_item_1")`. Each action's reply ends with the page it led to.

After changing the kit, refresh the copies here with `bash ../install.sh .`.
