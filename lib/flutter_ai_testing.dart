/// Lets an AI agent test a Flutter app the way a person does: in-app tools
/// for the flutter_ai_testing MCP server (`dart run flutter_ai_testing:mcp`).
///
/// Use it only from a debug-only entrypoint outside `lib/`; see the README.
library;

export 'package:marionette_flutter/marionette_flutter.dart' show MarionetteConfiguration;

export 'src/app/run.dart';
export 'src/app/tools.dart';
