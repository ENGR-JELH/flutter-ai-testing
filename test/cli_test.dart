import 'dart:convert';
import 'dart:io';

import 'package:flutter_ai_testing/src/cli/conf.dart';
import 'package:flutter_ai_testing/src/cli/keys.dart';
import 'package:flutter_ai_testing/src/cli/launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory app;

  setUp(() {
    app = Directory.systemTemp.createTempSync('ai_testing_app');
    File('${app.path}/pubspec.yaml').writeAsStringSync('name: demo\n');
  });
  tearDown(() => app.deleteSync(recursive: true));

  void write(String path, String text) => File('${app.path}/$path')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  group('AiTestingConf', () {
    test('reads values, repeats, comments and defaults', () {
      write('ai-testing.conf', '''
# comment
APP_ID=com.demo
KEYS_NOTE=first
KEYS_NOTE=second
ANDROID_PERMISSIONS=  A   B
EMPTY=
''');
      final conf = AiTestingConf.load(app);
      expect(conf.exists, isTrue);
      expect(conf.appId, 'com.demo');
      expect(conf.all('KEYS_NOTE'), ['first', 'second']);
      expect(conf.words('ANDROID_PERMISSIONS'), ['A', 'B']);
      expect(conf.get('EMPTY', 'fallback'), 'fallback');
      expect(conf.target, 'marionette/main.dart');
      expect(conf.uriFile('emulator:5554').path, endsWith('.marionette/emulator_5554.uri'));
    });

    test('findAppDir walks up to the pubspec', () {
      final deep = Directory('${app.path}/lib/a/b')..createSync(recursive: true);
      expect(findAppDir(deep.path)!.path, app.absolute.path);
    });
  });

  group('keys', () {
    setUp(() {
      write('ai-testing.conf', '''
KEYS_CLASS=Keys
KEYS_CONSTANTS=lib/keys.dart
KEYS_DYNAMIC=tab=nav_tab_<tab>
''');
      write('lib/keys.dart', "class Keys { static const String login = 'login_screen'; }");
      write('lib/login.dart', '''
final a = ValueKey('login_email_field');
final b = ValueKey(
  "login_button",
);
final c = ValueKey(Keys.login);
final d = ValueKey(Keys.tab(index));
final items = [{'key': 'menu_help'}];
''');
    });

    test('finds literal, split, constant, dynamic and map keys', () {
      final scanner = KeyScanner(AiTestingConf.load(app));
      final keys = scanner.keysIn(File('${app.path}/lib/login.dart')).map((k) => k.key);
      expect(keys, ['login_email_field', 'login_button', 'login_screen', 'nav_tab_<tab>', 'menu_help']);
    });

    test('check fails on contact-like keys', () {
      expect(checkKeys(AiTestingConf.load(app)).ok, isTrue);
      write('lib/bad.dart', "final k = ValueKey('someone@example.com');");
      final result = checkKeys(AiTestingConf.load(app));
      expect(result.ok, isFalse);
      expect(result.lines.join('\n'), isNot(contains('someone@example.com')));
    });

    test('index lists pages and their screen key', () {
      final r = writeKeyIndex(AiTestingConf.load(app));
      final md = File('${app.path}/${r.path}').readAsStringSync();
      expect(r.keys, 5);
      expect(md, contains('## `login.dart`'));
      expect(md, contains('Page check: `login_screen`'));
    });
  });

  test('newestFvmBin-style versions sort numerically', () {
    // Guards the bug where `stable` or 3.9 sorted above 3.47 as text.
    List<int> nums(String n) => n.split('.').map(int.tryParse).whereType<int>().toList();
    expect(nums('3.47.9'), [3, 47, 9]);
    expect(nums('stable'), isEmpty);
  });

  test('knownProblem returns fixed text, never the log', () {
    write('.marionette/x.log', 'secret line\nBUILD FAILED in 3s\n');
    final problem = knownProblem(File('${app.path}/.marionette/x.log'))!;
    expect(problem, startsWith('Android build failed'));
    expect(problem, isNot(contains('secret')));
  });

  test('defines refuses a value without the required text', () {
    write(
      'ai-testing.conf',
      'DEFINE_NAME=AI_TESTING_UNSET_NAME\nDEFINE_DEFAULT=https://prod.example.com\nDEFINE_MUST_CONTAIN=test\n',
    );
    expect(() => Launcher(AiTestingConf.load(app)).defines(), throwsA(isA<LaunchError>()));
  });

  group('MCP server', () {
    Future<List<Map<String, Object?>>> talk(List<Map<String, Object?>> requests) async {
      // Under flutter test, resolvedExecutable is the test engine, not dart.
      final root = Platform.environment['FLUTTER_ROOT'];
      final dart = root == null ? 'dart' : '$root/bin/dart';
      final p = await Process.start(dart, ['run', 'bin/mcp.dart'], workingDirectory: Directory.current.path);
      for (final r in requests) {
        p.stdin.writeln(jsonEncode({'jsonrpc': '2.0', ...r}));
      }
      await p.stdin.close();
      final lines = await p.stdout.transform(utf8.decoder).transform(const LineSplitter()).toList();
      await p.exitCode;
      return [for (final l in lines) (jsonDecode(l) as Map).cast<String, Object?>()];
    }

    test('initializes, lists own and Marionette tools, hides connect/get_logs', () async {
      final replies = await talk([
        {
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': '2024-11-05'},
        },
        {'method': 'notifications/initialized'},
        {'id': 2, 'method': 'tools/list'},
        {
          'id': 3,
          'method': 'tools/call',
          'params': {'name': 'tap', 'arguments': {}},
        },
        {
          'id': 4,
          'method': 'tools/call',
          'params': {'name': 'get_logs', 'arguments': {}},
        },
      ]);
      expect(replies.map((r) => r['id']), [1, 2, 3, 4]);
      expect((replies[0]['result'] as Map)['instructions'], contains('start_app'));
      final names = [for (final t in (replies[1]['result'] as Map)['tools'] as List) (t as Map)['name']];
      expect(names, containsAll(['start_app', 'where_am_i', 'tap', 'enter_text', 'get_interactive_elements']));
      expect(names, isNot(contains('connect')));
      expect(names, isNot(contains('get_logs')));
      final tap = replies[2]['result'] as Map;
      expect(tap['isError'], isTrue);
      expect(jsonEncode(tap), contains('no app running'));
      expect(jsonEncode(replies[3]['result']), contains('managed by this server'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
