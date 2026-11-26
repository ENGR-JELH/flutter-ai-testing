# Changelog

## 0.2.0

- Now a package: add it as a dev dependency and run `dart run flutter_ai_testing:init`.
  Nothing is copied into the app any more.
- The MCP server is Dart (`dart run flutter_ai_testing:mcp`): no Python needed. It runs
  `marionette_mcp` from the app's own dependencies, so no global install and no version mismatch.
- `runWithAiTesting(app.main, config: ...)` replaces the hand-written entrypoint.
- `GoRouterTools` reads the go_router page stack without the package depending on go_router.
- New commands: `run` (start the app yourself, then `attach`) and `keys check|index`.
- Removed `install.sh` and the Python and shell scripts.

## 0.1.0

- First version: in-app tools, Python MCP server, launch script and key scripts, installed into
  apps as copies.
