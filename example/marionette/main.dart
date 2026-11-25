// Debug-only entrypoint that lets an AI agent drive the app through
// Marionette. Never imported by lib/. Run it with
// scripts/ai-testing/marionette-run.sh <device-id>.
import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'package:ai_testing_example/main.dart' as app;

import 'app_tools.dart';
import 'marionette_config.dart';

void main() {
  if (kReleaseMode) {
    throw StateError(
      'marionette/main.dart is for debug and profile builds only',
    );
  }
  // Must come before the app starts: an app that initialises the binding
  // inside its own zone (crash reporters often do) would otherwise create a
  // second binding, and Flutter allows only one.
  MarionetteBinding.ensureInitialized(appMarionetteConfiguration);
  registerAppTools();
  app.main();
}
