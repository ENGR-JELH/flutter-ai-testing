// `dart run flutter_ai_testing:run <device-id> [flutter run args]`: start the
// app's Marionette entrypoint yourself, in a terminal. Agents then connect
// with the MCP server's attach tool. Keys r / R / q go to flutter run.
import 'dart:async';
import 'dart:io';

import 'package:flutter_ai_testing/src/cli/conf.dart';
import 'package:flutter_ai_testing/src/cli/launcher.dart';

Future<void> main(List<String> args) async {
  final dir = findAppDir();
  if (dir == null || args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln('usage (in a Flutter app): dart run flutter_ai_testing:run <device-id> [flutter run args]');
    stderr.writeln('devices: flutter devices');
    exit(64);
  }
  final RunningApp app;
  try {
    app = await Launcher(
      AiTestingConf.load(dir),
    ).start(args.first, extraArgs: args.skip(1).toList(), onLine: stdout.writeln);
  } on LaunchError catch (e) {
    stderr.writeln(e.message);
    exit(1);
  }

  StreamSubscription<List<int>>? keys;
  if (stdin.hasTerminal) {
    stdin
      ..echoMode = false
      ..lineMode = false;
  }
  keys = stdin.listen(app.process.stdin.add, onDone: () {});
  for (final signal in [ProcessSignal.sigint, if (!Platform.isWindows) ProcessSignal.sigterm]) {
    signal.watch().listen((_) => app.stop());
  }
  final code = await app.process.exitCode;
  await keys.cancel();
  if (stdin.hasTerminal) {
    stdin
      ..lineMode = true
      ..echoMode = true;
  }
  exit(code);
}
