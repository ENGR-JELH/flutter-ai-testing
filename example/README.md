# flutter_ai_testing example

A small app set up with flutter_ai_testing: a made-up sign-in, a list of three invented items, a
details page and a help page. Every page root and control has a key. Use it to try the package,
and to test the package after changing it (it depends on it by path).

| File | What it shows |
|---|---|
| `marionette/main.dart` | The entrypoint: `runWithAiTesting` with a go_router config (page names, sign-in, sign-out, shortcuts) |
| `ai-testing.conf` | Launch and key settings |
| `.mcp.json` | The MCP server registration |
| `docs/test-keys.md` | The generated key index |

## Try it

```sh
flutter pub get
```

Open this folder in an MCP client (it reads `.mcp.json`), then: `list_devices`,
`start_app(device: "<id>")`, and for example `enter_text(key: "login_name_field", input: "Test
User")`, `tap(key: "login_sign_in_button")`, `tap(key: "home_item_1")`. Each action's reply
ends with the page it led to.
