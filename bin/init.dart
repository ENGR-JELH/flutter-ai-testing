// `dart run flutter_ai_testing:init`: set up AI testing in a Flutter app.
// Creates only files that don't exist yet, and never touches lib/.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_ai_testing/src/cli/conf.dart';

Future<void> main(List<String> args) async {
  final dir = findAppDir();
  if (dir == null) {
    stderr.writeln('run it inside a Flutter app (no pubspec.yaml found)');
    exit(64);
  }
  final app = dir.path;
  final pubspec = File('$app/pubspec.yaml').readAsStringSync();
  final name = RegExp(r'^name:\s*(\w+)', multiLine: true).firstMatch(pubspec)?.group(1);
  if (name == null) {
    stderr.writeln('pubspec.yaml has no name');
    exit(1);
  }
  if (!RegExp(r'^\s+flutter_ai_testing:', multiLine: true).hasMatch(pubspec)) {
    stdout.writeln('note: add it first with `flutter pub add dev:flutter_ai_testing`');
  }
  final templates = await _templates();

  void create(String path, String content) {
    final f = File('$app/$path');
    if (f.existsSync()) {
      stdout.writeln('kept     $path (already there)');
      return;
    }
    f
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
    stdout.writeln('created  $path');
  }

  create('marionette/main.dart', '''
// Debug-only entrypoint that lets an AI agent drive the app. Never imported by
// lib/. Agents start it through the flutter_ai_testing MCP server; you can run
// it with `dart run flutter_ai_testing:run <device-id>`.
import 'package:flutter_ai_testing/flutter_ai_testing.dart';

// Your app's start-up function. If main() does more than runApp (config,
// Firebase, ...), keep it: this calls the whole main().
import 'package:$name/main.dart' as app;

void main() => runWithAiTesting(
      app.main,
      // Optional: page names, signed-in state, app facts and uiOnly shortcuts.
      // See https://pub.dev/packages/flutter_ai_testing#configure
      config: const AiTestingConfig(namespace: '$name'),
    );
''');

  final conf = File(
    '${templates.path}/ai-testing.conf',
  ).readAsStringSync().replaceFirst('APP_ID=com.example.app', 'APP_ID=${_applicationId(app) ?? 'com.example.app'}');
  create('ai-testing.conf', conf);
  create('docs/AUTOMATION-TESTING.md', File('${templates.path}/docs/AUTOMATION-TESTING.md').readAsStringSync());
  create('test_cases/README.md', File('${templates.path}/test_cases/README.md').readAsStringSync());

  _addMcpServer(app);
  _gitignore(app, '.marionette/');

  stdout.writeln('''

Next:
  1. Check APP_ID and the permissions in ai-testing.conf.
  2. Give each page a root key ending in _screen, e.g. ValueKey('login_screen'),
     and key the controls tests use. Then: dart run flutter_ai_testing:keys index
  3. Restart your agent so it loads the MCP server, then ask it to list_devices
     and start_app.''');
}

Future<Directory> _templates() async {
  final lib = await Isolate.resolvePackageUri(Uri.parse('package:flutter_ai_testing/'));
  return Directory.fromUri(lib!.resolve('../templates/'));
}

String? _applicationId(String app) {
  for (final name in ['build.gradle.kts', 'build.gradle']) {
    final f = File('$app/android/app/$name');
    if (!f.existsSync()) continue;
    final m = RegExp(r'''applicationId\s*=?\s*["']([\w.]+)["']''').firstMatch(f.readAsStringSync());
    if (m != null) return m.group(1);
  }
  return null;
}

void _addMcpServer(String app) {
  final f = File('$app/.mcp.json');
  Map<String, Object?> json = {};
  if (f.existsSync()) {
    try {
      json = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
    } on FormatException {
      stdout.writeln('kept     .mcp.json (not valid JSON: add the server by hand)');
      return;
    }
  }
  final servers = (json['mcpServers'] as Map?)?.cast<String, Object?>() ?? {};
  if (servers.containsKey('flutter-ai-testing')) {
    stdout.writeln('kept     .mcp.json (flutter-ai-testing already there)');
    return;
  }
  servers['flutter-ai-testing'] = {
    'command': 'dart',
    'args': ['run', 'flutter_ai_testing:mcp'],
  };
  json['mcpServers'] = servers;
  f.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
  stdout.writeln('updated  .mcp.json (flutter-ai-testing server)');
}

void _gitignore(String app, String line) {
  final f = File('$app/.gitignore');
  final text = f.existsSync() ? f.readAsStringSync() : '';
  if (LineSplitter.split(text).any((l) => l.trim() == line)) return;
  f.writeAsStringSync(
    '${text.isEmpty || text.endsWith('\n') ? text : '$text\n'}# flutter_ai_testing run files\n$line\n',
  );
  stdout.writeln('updated  .gitignore ($line)');
}
