import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'tools.dart';

/// Starts the app with Marionette and the agent tools turned on. Call it from
/// the debug-only entrypoint (`marionette/main.dart`, made by
/// `dart run flutter_ai_testing:init`), never from `lib/`:
///
/// ```dart
/// void main() => runWithAiTesting(app.main);
/// ```
///
/// [config] adds app facts and shortcuts; without it the tools still report
/// the `*_screen` keys on screen, dialogs and loading. [marionette] teaches
/// Marionette the app's own buttons and fields.
///
/// Don't pass a Marionette log collector: debug output often contains
/// personal data, and the agent would read it.
void runWithAiTesting(
  void Function() appMain, {
  AiTestingConfig? config,
  MarionetteConfiguration marionette = const MarionetteConfiguration(),
}) {
  if (kReleaseMode) {
    throw StateError('flutter_ai_testing is for debug and profile builds only');
  }
  // Must come before the app starts: an app that initialises the binding
  // inside its own zone (crash reporters often do) would otherwise create a
  // second binding, and Flutter allows only one.
  MarionetteBinding.ensureInitialized(marionette);
  registerAiTestingTools(config ?? const AiTestingConfig(namespace: 'app'));
  appMain();
}

/// Helpers for apps that use go_router, without this package depending on
/// it: pass the app's `GoRouter`.
///
/// ```dart
/// AiTestingConfig(
///   namespace: 'myapp',
///   routeStack: () => GoRouterTools.stack(router),
///   location: () => GoRouterTools.location(router),
///   openRoute: (name, {required replace}) =>
///       GoRouterTools.open(router, name, replace: replace),
/// )
/// ```
abstract final class GoRouterTools {
  /// The page stack by route name, pushed pages included. A pushed page whose
  /// `extra` is a map with a `routeName` string is named by it.
  static List<String> stack(Object router) {
    final dynamic config = (router as dynamic).routerDelegate.currentConfiguration;
    final stack = <String>[];
    for (final dynamic match in config.matches as Iterable) {
      final type = match.runtimeType.toString();
      if (type.startsWith('ImperativeRouteMatch')) {
        final dynamic inner = match.matches;
        final dynamic extra = inner.extra;
        final name = extra is Map ? extra['routeName'] : null;
        stack.add(name is String ? name : _name(inner.last.route));
      } else {
        stack.add(_name(match.route));
      }
    }
    return stack;
  }

  /// The current location's path.
  static String location(Object router) => ((router as dynamic).routerDelegate.currentConfiguration.uri as Uri).path;

  /// Opens a named route: pushes it, or replaces the stack with [replace].
  static void open(Object router, String name, {required bool replace}) {
    final dynamic r = router;
    if (replace) {
      r.goNamed(name);
    } else {
      r.pushNamed(name);
    }
  }

  static String _name(dynamic route) {
    try {
      final dynamic name = route.name;
      if (name is String) return name;
    } catch (_) {}
    try {
      final dynamic path = route.path;
      if (path is String) return path;
    } catch (_) {}
    return route.runtimeType.toString();
  }
}
