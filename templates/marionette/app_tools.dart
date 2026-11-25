// App-specific settings for the AI testing tools. The tools themselves are in
// ai_testing.dart, a copy installed by flutter-ai-testing: don't edit that one.
//
// Return only facts that are safe to show an AI agent: route names, keys,
// booleans, codes. Never names, contact details or other personal data.
import 'package:go_router/go_router.dart';

// TODO: import the app's router and session helpers.
// import 'package:my_app/router.dart';

import 'ai_testing.dart';

late final GoRouter _router; // TODO: = the app's GoRouter

void registerAppTools() {
  registerAiTestingTools(
    AiTestingConfig(
      namespace: 'myapp', // tools become myapp.whereAmI and so on
      routeStack: _routeStack,
      location: () => _router.routerDelegate.currentConfiguration.uri.path,
      // isSignedIn: () => Session.instance.isSignedIn,
      // appState: () => {'tab': currentTabName()},
      // signOut: () async {
      //   await Session.instance.signOut();
      //   _router.goNamed('login');
      // },
      uiOnlyRoutes: const [], // route names that open without extra objects
      openRoute: (name, {required replace}) =>
          replace ? _router.goNamed(name) : _router.pushNamed(name),
      uiOnlyScreens: const {}, // name -> () => push the screen
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
