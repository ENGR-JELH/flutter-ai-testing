// `dart run flutter_ai_testing:keys check|index`: check the app's test keys,
// or regenerate its key index (docs/test-keys.md by default).
import 'dart:io';

import 'package:flutter_ai_testing/src/cli/conf.dart';
import 'package:flutter_ai_testing/src/cli/keys.dart';

void main(List<String> args) {
  final dir = findAppDir();
  if (dir == null || args.length != 1 || !const {'check', 'index'}.contains(args.first)) {
    stderr.writeln('usage (in a Flutter app): dart run flutter_ai_testing:keys check|index');
    exit(64);
  }
  final conf = AiTestingConf.load(dir);
  if (args.first == 'check') {
    final result = checkKeys(conf);
    result.lines.forEach(stdout.writeln);
    exit(result.ok ? 0 : 1);
  }
  final r = writeKeyIndex(conf);
  stdout.writeln('wrote ${r.path} (${r.keys} keys, ${r.pages} pages)');
}
