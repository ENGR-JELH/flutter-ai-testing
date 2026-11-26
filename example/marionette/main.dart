// Debug-only entrypoint that lets an AI agent drive the app. Never imported by
// lib/. Agents start it through the flutter_ai_testing MCP server; you can run
// it with `dart run flutter_ai_testing:run <device-id>`.
//
// Return only facts that are safe to show an AI agent: route names, keys,
// booleans, codes. Never names, contact details or other personal data.
import 'package:flutter_ai_testing/flutter_ai_testing.dart';

import 'package:ai_testing_example/main.dart' as app;

void main() => runWithAiTesting(
      app.main,
      config: AiTestingConfig(
        namespace: 'example',
        routeStack: () => GoRouterTools.stack(app.router),
        location: () => GoRouterTools.location(app.router),
        isSignedIn: () => app.Session.signedIn,
        appState: () => {'itemCount': app.items.length},
        signOut: () async {
          app.Session.signedIn = false;
          app.router.goNamed('login');
        },
        uiOnlyRoutes: const ['login', 'help'],
        openRoute: (name, {required replace}) =>
            GoRouterTools.open(app.router, name, replace: replace),
      ),
    );
