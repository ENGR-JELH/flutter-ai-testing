import 'package:marionette_flutter/marionette_flutter.dart';

/// Teaches Marionette the app's own controls. Without this it only sees stock
/// Material widgets, so custom buttons and fields would be invisible to the
/// agent. Add each custom button, field, switch and list tile the app uses:
///
///   isInteractiveElement: (element) => switch (element.widget) {
///     AppButton() || AppTextField() => true,
///     _ => false,
///   },
///   extractText: (element) => switch (element.widget) {
///     AppButton(:final label) => label,
///     _ => null,
///   },
///
/// Don't add a log collector: debug output often contains personal data, and
/// the agent would read it.
final appMarionetteConfiguration = MarionetteConfiguration(
  isInteractiveElement: (element) => false,
  extractText: (element) => null,
);
