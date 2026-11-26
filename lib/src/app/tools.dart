import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

/// What the tools need to know about one app. Everything is a callback, so
/// the kit doesn't depend on a router, a state library or the app's models.
///
/// Return only facts that are safe to show an AI agent: route names, test
/// keys, booleans, codes. Never names, contact details or other personal data.
class AiTestingConfig {
  const AiTestingConfig({
    required this.namespace,
    this.routeStack = _noStack,
    this.location,
    this.isSignedIn,
    this.appState,
    this.signOut,
    this.uiOnlyRoutes = const [],
    this.openRoute,
    this.uiOnlyScreens = const {},
    this.screensNeedSignIn = true,
    this.screenKeySuffix = '_screen',
    this.loadingWidgetTypes = const {'CircularProgressIndicator', 'CupertinoActivityIndicator'},
    this.maxSettle = const Duration(seconds: 2),
  });

  /// Tool name prefix, for example `myapp` gives `myapp.whereAmI`.
  final String namespace;

  /// The open pages, bottom first, by name. For go_router use
  /// [GoRouterTools.stack]. Without it, `visibleScreens` still shows the pages.
  final List<String> Function() routeStack;

  static List<String> _noStack() => const [];

  /// The current location (path), if the app has one.
  final String Function()? location;

  /// Whether a user is signed in. Leave null for apps without sign-in.
  final bool Function()? isSignedIn;

  /// Extra non-personal facts to report, such as the selected tab.
  final Map<String, Object?> Function()? appState;

  /// Ends the session and shows the signed-out start page. Enables the
  /// `setupSignedOut` tool when set.
  final Future<void> Function()? signOut;

  /// Route names `uiOnlyOpenRoute` accepts.
  final List<String> uiOnlyRoutes;

  /// Opens a route by name. `replace` replaces the stack instead of pushing.
  final void Function(String name, {required bool replace})? openRoute;

  /// Screens without a route of their own that `uiOnlyOpenScreen` can push.
  final Map<String, void Function()> uiOnlyScreens;

  /// Whether `uiOnlyOpenScreen` refuses while signed out.
  final bool screensNeedSignIn;

  /// Keys ending in this mark a page root, reported in `visibleScreens`.
  final String screenKeySuffix;

  /// Widget types that mean "still loading".
  final Set<String> loadingWidgetTypes;

  /// The longest a tool waits for animations to finish before answering.
  final Duration maxSettle;
}

/// What is on screen now.
class ScreenScan {
  const ScreenScan(this.screens, this.dialogs, this.loading);

  /// `*_screen` test keys on screen, bottom page first.
  final List<String> screens;

  /// Open dialogs and sheets, by widget type (never their text).
  final List<String> dialogs;

  /// Whether a loading indicator is showing.
  final bool loading;
}

/// Walks the visible widget tree. Subtrees hidden by Offstage or a disabled
/// TickerMode (inactive tabs, routes kept alive off screen) are skipped.
ScreenScan scanScreen(AiTestingConfig config) {
  final screens = <String>[];
  final dialogs = <String>{};
  var loading = false;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is Offstage && widget.offstage) return;
    if (widget is TickerMode && !widget.enabled) return;
    final key = widget.key;
    if (key is ValueKey<String> && key.value.endsWith(config.screenKeySuffix)) {
      screens.add(key.value);
    }
    final type = widget.runtimeType.toString();
    if (!type.startsWith('_') && (type.endsWith('Dialog') || type.endsWith('BottomSheet'))) {
      dialogs.add(type);
    }
    if (config.loadingWidgetTypes.contains(type)) loading = true;
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return ScreenScan(screens, dialogs.toList(), loading);
}

/// The `whereAmI` answer.
Map<String, Object?> whereAmI(AiTestingConfig config) {
  final scan = scanScreen(config);
  return {
    if (config.location != null) 'location': config.location!(),
    'stack': config.routeStack(),
    'visibleScreens': scan.screens,
    'dialogs': scan.dialogs,
    'loading': scan.loading,
    if (config.isSignedIn != null) 'signedIn': config.isSignedIn!(),
    ...?config.appState?.call(),
  };
}

/// Waits until no frame is scheduled (route and dialog animations done), for
/// at most [AiTestingConfig.maxSettle]: a spinner or a live map keeps
/// scheduling frames.
Future<void> settle(AiTestingConfig config) async {
  const step = Duration(milliseconds: 100);
  final deadline = DateTime.now().add(config.maxSettle);
  await Future<void>.delayed(step);
  while (DateTime.now().isBefore(deadline)) {
    if (!SchedulerBinding.instance.hasScheduledFrame) return;
    await Future<void>.delayed(step);
  }
}

/// Registers the tools. Call it in the Marionette entrypoint, after
/// `MarionetteBinding.ensureInitialized` and before the app starts.
///
/// - `<ns>.whereAmI`: read-only, any time.
/// - `<ns>.setupSignedOut`: test setup, when [AiTestingConfig.signOut] is set.
/// - `<ns>.uiOnlyOpenRoute` / `<ns>.uiOnlyOpenScreen`: shortcuts for checking
///   one page's layout only. A normal test reaches pages by tapping.
void registerAiTestingTools(AiTestingConfig config) {
  final ns = config.namespace;

  Future<MarionetteExtensionResult> answer() async {
    await settle(config);
    return MarionetteExtensionResult.success(whereAmI(config));
  }

  registerMarionetteExtension(
    name: '$ns.whereAmI',
    description:
        'Read-only. Returns the page stack by name, the visible '
        '*${config.screenKeySuffix} test keys (bottom page first), open '
        'dialogs (by type), whether a spinner is showing, whether a user is '
        'signed in, and app facts. Use it after every step.',
    inputSchema: const ExtensionInputSchema(properties: {}),
    callback: (_) => answer(),
  );

  final signOut = config.signOut;
  if (signOut != null) {
    registerMarionetteExtension(
      name: '$ns.setupSignedOut',
      description:
          'TEST SETUP, not a test step. Ends the session and shows the '
          'signed-out start page, so a case that starts "signed out" has a '
          'known state. To test signing out itself, tap the sign-out button.',
      inputSchema: const ExtensionInputSchema(properties: {}),
      callback: (_) async {
        await signOut();
        return answer();
      },
    );
  }

  final openRoute = config.openRoute;
  if (openRoute != null && config.uiOnlyRoutes.isNotEmpty) {
    registerMarionetteExtension(
      name: '$ns.uiOnlyOpenRoute',
      description:
          'UI-ONLY SHORTCUT. Opens a route directly, skipping the normal user '
          "path. Use it only to check a single page's layout. Never use it in "
          'a normal test case: navigate by tapping instead.',
      inputSchema: ExtensionInputSchema(
        properties: {
          'name': ExtensionParam.string(description: 'Route name.', enumValues: config.uiOnlyRoutes),
          'mode': ExtensionParam.string(
            description:
                'push keeps the current page under it (default); go '
                'replaces the stack.',
            enumValues: const ['push', 'go'],
            defaultValue: 'push',
          ),
        },
        required: const ['name'],
      ),
      callback: (params) async {
        final name = params['name'] ?? '';
        if (!config.uiOnlyRoutes.contains(name)) {
          return MarionetteExtensionResult.error(1, 'Unknown route "$name". Supported: ${config.uiOnlyRoutes}');
        }
        openRoute(name, replace: params['mode'] == 'go');
        return answer();
      },
    );
  }

  if (config.uiOnlyScreens.isNotEmpty) {
    registerMarionetteExtension(
      name: '$ns.uiOnlyOpenScreen',
      description:
          'UI-ONLY SHORTCUT. Pushes a screen that has no route of its own, '
          "skipping the normal user path. Use it only to check a single page's "
          'layout. Never use it in a normal test case: navigate by tapping '
          'instead.',
      inputSchema: ExtensionInputSchema(
        properties: {
          'screen': ExtensionParam.string(
            description: 'Screen to open.',
            enumValues: config.uiOnlyScreens.keys.toList(),
          ),
        },
        required: const ['screen'],
      ),
      callback: (params) async {
        final open = config.uiOnlyScreens[params['screen']];
        if (open == null) {
          return MarionetteExtensionResult.error(
            1,
            'Unknown screen "${params['screen']}". '
            'Supported: ${config.uiOnlyScreens.keys.toList()}',
          );
        }
        final signedIn = config.isSignedIn?.call() ?? true;
        if (config.screensNeedSignIn && !signedIn) {
          return MarionetteExtensionResult.error(2, 'Sign in first: these screens need a session.');
        }
        open();
        return answer();
      },
    );
  }
}
