// App-specific settings for the AI testing tools. The tools themselves are in
// ai_testing.dart, a copy installed by flutter-ai-testing: don't edit that one.
//
// Return only facts that are safe to show an AI agent: route names, keys,
// booleans, codes. Never names, contact details or other personal data.
import 'package:go_router/go_router.dart';

import 'package:ai_testing_example/main.dart';

import 'ai_testing.dart';

GoRouter get _router => router;

void registerAppTools() {
  registerAiTestingTools(
    AiTestingConfig(
      namespace: 'example',
      routeStack: _routeStack,
      location: () => _router.routerDelegate.currentConfiguration.uri.path,
      isSignedIn: () => Session.signedIn,
      appState: () => {'itemCount': items.length},
      signOut: () async {
        Session.signedIn = false;
        _router.goNamed('login');
      },
      uiOnlyRoutes: const ['login', 'help'],
      openRoute: (name, {required replace}) =>
          replace ? _router.goNamed(name) : _router.pushNamed(name),
    ),
  );
}

/// go_router's page stack by route name, pushed pages included.
List<String> _routeStack() {
  final stack = <String>[];
  for (final match in _router.routerDelegate.currentConfiguration.matches) {
    if (match is ImperativeRouteMatch) {
      stack.add(match.matches.last.route.name ?? match.matches.last.route.path);
    } else if (match is RouteMatch) {
      stack.add(match.route.name ?? match.route.path);
    }
  }
  return stack;
}
