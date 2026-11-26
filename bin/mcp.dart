// `dart run flutter_ai_testing:mcp`: the MCP server, over stdin/stdout.
// Register it once per project in .mcp.json (init does it for you).
import 'package:flutter_ai_testing/src/cli/mcp_server.dart';

Future<void> main() => McpServer().serve();
