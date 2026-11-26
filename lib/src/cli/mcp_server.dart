// Pure Dart (no Flutter): the flutter_ai_testing MCP server.
//
// Lets any MCP client (Claude Code, Codex, Cursor, Copilot, ...) start a
// Flutter app on a device and drive it. It runs one marionette_mcp per device
// (from this package's own dependencies) and passes its tools through, each
// with an optional `device`, plus its own tools. App logs go to a file and are
// never returned: debug output can contain personal data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'conf.dart';
import 'keys.dart';
import 'launcher.dart';

const serverVersion = '0.2.0';

const instructions = '''
Tools to test a Flutter app on Android and iOS the way a person does.

1. list_devices, then start_app(device). It builds, installs, grants OS
   permissions and connects; the first build can take minutes. If it returns
   "starting", call app_status until it is running.
2. Drive the app with tap / enter_text / scroll_to / swipe / press_back_button,
   targeting controls by test key (see the app's docs/test-keys.md). Read the
   screen with get_interactive_elements.
3. Each action's reply ends with "after: {...}", the where_am_i answer once the
   screen has settled and loading has finished (up to 15 s): page stack,
   *_screen keys on screen (bottom page first), open dialogs, loading, signed
   in. Check it before the next step. If loading is still true, call
   where_am_i again until it is false.

Rules:
- Reach pages the normal way, by tapping. The app's uiOnly... tools skip the
  user path: use them only when asked to check one page's layout, and say so.
- Never type real people's data. Use the test account the user gives you for
  that run, and don't write it to any file.
- Don't take screenshots of pages that show personal data unless asked.
- On Android, Back on the first page closes the app: prefer the page's own
  back buttons.
- OS dialogs (permissions, keyboard) are not visible to these tools.
- The app's own guide is docs/AUTOMATION-TESTING.md (page map, test cases).
''';

/// Marionette tools not passed through: the server manages connections, and
/// logs can contain personal data.
const hiddenTools = {'connect', 'disconnect', 'get_logs'};

/// Passed-through tools that change the screen: their reply also carries the
/// where_am_i answer once the screen settles.
const actionTools = {
  'tap', 'secondary_tap', 'double_tap', 'long_press', 'swipe', 'pinch_zoom', 'press_back_button', //
  'scroll_to', 'enter_text', 'press_key', 'hot_restart', 'hot_reload', 'call_custom_extension',
};

class ToolError implements Exception {
  ToolError(this.message);
  final String message;
  @override
  String toString() => message;
}

Duration _envSeconds(String name, int fallback) =>
    Duration(milliseconds: ((double.tryParse(Platform.environment[name] ?? '') ?? fallback) * 1000).round());

final callTimeout = _envSeconds('AI_TESTING_CALL_TIMEOUT', 45);
final loadingWait = _envSeconds('AI_TESTING_LOADING_WAIT', 15);

void _log(String message) => stderr.writeln('[flutter_ai_testing] $message');

/// One marionette_mcp process, connected to one app.
class Marionette {
  Marionette._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final msg = jsonDecode(line) as Map<String, Object?>;
              final pending = _pending.remove(msg['id']);
              pending?.complete(msg);
            } catch (_) {}
          },
          onDone: () {
            for (final p in _pending.values) {
              p.completeError(ToolError('marionette_mcp stopped'));
            }
            _pending.clear();
          },
        );
    _process.stderr.drain<void>();
  }

  final Process _process;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  var _id = 0;
  String? uri;
  String? namespace;

  static Future<Marionette> start() async {
    final command = await _marionetteCommand();
    final process = await Process.start(command.first, command.skip(1).toList());
    final m = Marionette._(process);
    await m.request('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'flutter_ai_testing', 'version': serverVersion},
    });
    m._process.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));
    return m;
  }

  /// marionette_mcp from this package's dependencies, run by the same Dart as
  /// this server, so its version always matches marionette_flutter in the app.
  /// Falls back to a globally activated marionette_mcp.
  static Future<List<String>> _marionetteCommand() async {
    final lib = await Isolate.resolvePackageUri(Uri.parse('package:marionette_mcp/'));
    final config = await Isolate.packageConfig;
    if (lib != null && config != null) {
      final bin = File.fromUri(lib.resolve('../bin/marionette_mcp.dart'));
      if (bin.existsSync()) {
        return [Platform.resolvedExecutable, '--packages=${config.toFilePath()}', bin.path];
      }
    }
    final global = which('marionette_mcp') ?? '$homeDir/.pub-cache/bin/marionette_mcp';
    if (File(global).existsSync()) return [global];
    throw ToolError('marionette_mcp not found: add flutter_ai_testing to dev_dependencies and run pub get');
  }

  Future<Map<String, Object?>> request(String method, Map<String, Object?> params, {Duration? timeout}) async {
    final id = ++_id;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _process.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    final reply = await completer.future.timeout(
      timeout ?? callTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw ToolError(
          'no answer from the app within ${(timeout ?? callTimeout).inSeconds}s: it may be in the background, '
          'behind another app, or stopped at a breakpoint. Bring it to the front and retry.',
        );
      },
    );
    final error = reply['error'];
    if (error is Map) throw ToolError('${error['message'] ?? 'marionette error'}');
    return (reply['result'] as Map).cast<String, Object?>();
  }

  Future<Map<String, Object?>> call(String name, Map<String, Object?> args) =>
      request('tools/call', {'name': name, 'arguments': args});

  Future<void> connect(String address) async {
    final result = await call('connect', {'uri': address});
    if (result['isError'] == true) throw ToolError(textOf(result).isEmpty ? 'could not connect' : textOf(result));
    uri = address;
    namespace = null;
  }

  void close() => _process.kill();
}

String textOf(Map<String, Object?> result) => [
  for (final c in (result['content'] as List? ?? const []))
    if (c is Map && c['type'] == 'text') '${c['text']}',
].join();

/// An app started (or attached) on one device.
class Session {
  Session(this.device, this.conf);

  final String device;
  final AiTestingConf conf;
  RunningApp? app;
  Marionette? marionette;

  String get state {
    if (app != null && app!.exited) return 'exited (${app!.exitCode})';
    if (marionette?.uri != null) return 'running';
    return app != null ? 'starting' : 'attached';
  }

  Future<bool> tryConnect() async {
    if (marionette?.uri != null) return true;
    final file = conf.uriFile(device);
    if (!file.existsSync()) return false;
    final address = file.readAsStringSync().trim();
    if (address.isEmpty) return false;
    marionette ??= await Marionette.start();
    await marionette!.connect(address);
    return true;
  }

  Future<void> stop() async {
    marionette?.close();
    marionette = null;
    await app?.stop();
  }

  Map<String, Object?> summary() => {
    'device': device,
    'app': conf.appDir.path,
    'state': state,
    'problem': knownProblem(conf.logFile(device)),
  };
}

class McpServer {
  final sessions = <String, Session>{};
  List<Map<String, Object?>>? _passthrough;

  Directory appDirArg(Map<String, Object?> args) {
    final raw = args['app_dir'] as String? ?? Platform.environment['AI_TESTING_APP_DIR'] ?? Directory.current.path;
    final dir = findAppDir(raw.replaceFirst(RegExp(r'^~'), homeDir));
    if (dir == null) throw ToolError('no Flutter app (pubspec.yaml) at or above $raw');
    return dir;
  }

  Session sessionFor(Map<String, Object?> args) {
    final device = args['device'] as String?;
    if (device != null && device.isNotEmpty) {
      return sessions[device] ?? (throw ToolError('no app on $device: call start_app or attach first'));
    }
    final live = sessions.values.where((s) => const {'running', 'attached', 'starting'}.contains(s.state)).toList();
    if (live.length == 1) return live.single;
    if (live.isEmpty) throw ToolError('no app running: call start_app (or attach) first');
    throw ToolError('several apps running, pass device: ${live.map((s) => s.device).toList()}');
  }

  Future<Marionette> connected(Session session) async {
    if (!await session.tryConnect()) {
      throw ToolError('app on ${session.device} is ${session.state}, not connected yet: call app_status');
    }
    return session.marionette!;
  }

  // ------------------------------------------------------------ own tools

  Future<String> listDevices(Map<String, Object?> args) async {
    final dir = findAppDir() ?? Directory.current;
    final command = Launcher(AiTestingConf.load(dir)).flutterCommand();
    final r = await Process.run(runInShell: needsShell(command.first), command.first, [
      ...command.skip(1),
      'devices',
      '--machine',
    ], workingDirectory: dir.path);
    final out = '${r.stdout}';
    final start = out.indexOf('[');
    if (start < 0) throw ToolError('flutter devices failed');
    final devices = (jsonDecode(out.substring(start)) as List).cast<Map>();
    final rows = [
      for (final d in devices)
        if ('${d['targetPlatform']}'.startsWith('android') || '${d['targetPlatform']}'.startsWith('ios'))
          {'id': d['id'], 'name': d['name'], 'platform': d['targetPlatform'], 'emulator': d['emulator']},
    ];
    return const JsonEncoder.withIndent(' ').convert(rows);
  }

  Future<String> startApp(Map<String, Object?> args) async {
    final device = args['device'] as String? ?? '';
    if (device.isEmpty) throw ToolError('pass device (see list_devices)');
    final conf = AiTestingConf.load(appDirArg(args));
    if (!conf.exists) {
      throw ToolError('${conf.appDir.path} has no ai-testing.conf: run `dart run flutter_ai_testing:init` there');
    }
    final wait = Duration(seconds: (args['wait_seconds'] as num?)?.toInt() ?? 300);
    final old = sessions[device];
    if (old != null && const {'running', 'starting'}.contains(old.state)) {
      if (old.conf.appDir.path == conf.appDir.path) return _waitFor(old, wait);
      await old.stop();
    }
    final session = Session(device, conf);
    final extra = switch (args['flutter_args']) {
      final List<Object?> l => l.map((e) => '$e').toList(),
      final String s => s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList(),
      _ => const <String>[],
    };
    try {
      session.app = await Launcher(conf).start(device, extraArgs: extra);
    } on LaunchError catch (e) {
      throw ToolError(e.message);
    }
    sessions[device] = session;
    _log('starting ${conf.appDir.path} on $device (log: ${conf.logFile(device).path})');
    return _waitFor(session, wait);
  }

  Future<String> _waitFor(Session session, Duration wait) async {
    final deadline = DateTime.now().add(wait);
    while (true) {
      if (await session.tryConnect()) return jsonEncode(session.summary());
      if (session.app?.exited ?? false) throw ToolError(jsonEncode(session.summary()));
      if (DateTime.now().isAfter(deadline)) {
        return jsonEncode({...session.summary(), 'note': 'still starting: call app_status later'});
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<String> attach(Map<String, Object?> args) async {
    final device = args['device'] as String? ?? '';
    if (device.isEmpty) throw ToolError('pass device');
    final session = Session(device, AiTestingConf.load(appDirArg(args)));
    if (!await session.tryConnect()) {
      throw ToolError(
        'no saved address ${session.conf.uriFile(device).path}: start the app with start_app or the run command',
      );
    }
    sessions[device] = session;
    return jsonEncode(session.summary());
  }

  Future<String> appStatus(Map<String, Object?> args) async {
    for (final s in sessions.values) {
      if (s.state == 'starting') {
        try {
          await s.tryConnect();
        } on ToolError catch (_) {}
      }
    }
    if (sessions.isEmpty) return 'no apps started';
    return const JsonEncoder.withIndent(' ').convert([for (final s in sessions.values) s.summary()]);
  }

  Future<String> stopApp(Map<String, Object?> args) async {
    final session = sessionFor(args);
    await session.stop();
    sessions.remove(session.device);
    return 'stopped the app on ${session.device}';
  }

  Future<String> whereAmI(Map<String, Object?> args) async {
    final m = await connected(sessionFor(args));
    if (m.namespace == null) {
      final listing = textOf(await m.call('list_custom_extensions', {}));
      final match = RegExp(r'([\w-]+)\.whereAmI').firstMatch(listing);
      if (match == null) {
        throw ToolError('the app registers no <ns>.whereAmI tool: does its entrypoint call runWithAiTesting?');
      }
      m.namespace = match.group(1);
    }
    final body = textOf(await m.call('call_custom_extension', {'extension': '${m.namespace}.whereAmI', 'args': {}}));
    final start = body.indexOf('{');
    if (start < 0) throw ToolError(body.isEmpty ? 'whereAmI failed' : body);
    final answer = (jsonDecode(body.substring(start)) as Map).cast<String, Object?>()
      ..remove('type')
      ..remove('method')
      ..remove('status');
    return jsonEncode(answer);
  }

  Future<String> checkKeysTool(Map<String, Object?> args) async {
    final result = checkKeys(AiTestingConf.load(appDirArg(args)));
    if (!result.ok) throw ToolError(result.lines.join('\n'));
    return result.lines.join('\n');
  }

  Future<String> keyIndexTool(Map<String, Object?> args) async {
    final r = writeKeyIndex(AiTestingConf.load(appDirArg(args)));
    return 'wrote ${r.path} (${r.keys} keys, ${r.pages} pages)';
  }

  late final Map<String, (Future<String> Function(Map<String, Object?>), String, Map<String, Object?>)> ownTools = {
    'list_devices': (listDevices, 'Android and iOS devices, emulators and simulators that can run the app.', {}),
    'start_app': (
      startApp,
      "Build, install and launch the app's Marionette entrypoint on a device, grant OS permissions and connect. "
          'Waits up to wait_seconds (default 300); the first build can take minutes. Starting again on the same '
          'device and app just waits for it.',
      {
        'app_dir': {'type': 'string', 'description': "Flutter app folder (default: the server's working directory)"},
        'device': {'type': 'string', 'description': 'Device id from list_devices'},
        'wait_seconds': {'type': 'integer', 'description': 'How long to wait for the app (default 300)'},
        'flutter_args': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Extra flutter run arguments',
        },
      },
    ),
    'attach': (
      attach,
      'Connect to an app already started with `dart run flutter_ai_testing:run` (reads its saved address).',
      {
        'app_dir': {'type': 'string'},
        'device': {'type': 'string'},
      },
    ),
    'app_status': (
      appStatus,
      'State of each started app: starting, running, exited, and a known problem if any. Never returns log text.',
      {},
    ),
    'stop_app': (
      stopApp,
      'Stop the app on a device.',
      {
        'device': {'type': 'string'},
      },
    ),
    'where_am_i': (
      whereAmI,
      'Read-only. Page stack by name, *_screen keys on screen (bottom page first), open dialogs by type, loading, '
          'signed in, and app facts. Call it after every step.',
      {
        'device': {'type': 'string'},
      },
    ),
    'check_keys': (
      checkKeysTool,
      "Check the app's test keys (fails on keys that look like contact data).",
      {
        'app_dir': {'type': 'string'},
      },
    ),
    'key_index': (
      keyIndexTool,
      "Regenerate the app's test-key index (docs/test-keys.md by default).",
      {
        'app_dir': {'type': 'string'},
      },
    ),
  };

  /// Marionette's own tools, read once from a throwaway marionette_mcp.
  Future<List<Map<String, Object?>>> passthroughTools() async {
    if (_passthrough != null) return _passthrough!;
    try {
      final probe = await Marionette.start();
      final tools = ((await probe.request('tools/list', {}))['tools'] as List).cast<Map>();
      probe.close();
      _passthrough = [
        for (final t in tools)
          if (!hiddenTools.contains(t['name']))
            {
              'name': t['name'],
              'description': t['description'] ?? '',
              'inputSchema': {
                ...?(t['inputSchema'] as Map?)?.cast<String, Object?>(),
                'type': 'object',
                'properties': {
                  ...?((t['inputSchema'] as Map?)?['properties'] as Map?)?.cast<String, Object?>(),
                  'device': {'type': 'string', 'description': 'Device id; optional when one app is running'},
                },
              },
            },
      ];
    } on Object catch (e) {
      _log('marionette tools unavailable: $e');
      return const [];
    }
    return _passthrough!;
  }

  Future<List<Map<String, Object?>>> listTools() async => [
    for (final e in ownTools.entries)
      {
        'name': e.key,
        'description': e.value.$2,
        'inputSchema': {'type': 'object', 'properties': e.value.$3},
      },
    ...await passthroughTools(),
  ];

  Future<Map<String, Object?>> callTool(String name, Map<String, Object?> args) async {
    final own = ownTools[name];
    if (own != null) {
      return {
        'content': [
          {'type': 'text', 'text': await own.$1(args)},
        ],
      };
    }
    if (hiddenTools.contains(name)) throw ToolError('$name is managed by this server: use start_app / attach');
    if (!(await passthroughTools()).any((t) => t['name'] == name)) throw ToolError('unknown tool $name');
    final session = sessionFor(args);
    final forwarded = Map<String, Object?>.of(args)..remove('device');
    var result = await (await connected(session)).call(name, forwarded);
    if (actionTools.contains(name) && result['isError'] != true) {
      // Wait for the screen to settle (whereAmI does) and for loading to end,
      // then report where the action led, so the next step never races it.
      try {
        var after = await whereAmI({'device': session.device});
        final deadline = DateTime.now().add(loadingWait);
        while ((jsonDecode(after) as Map)['loading'] == true && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(seconds: 1));
          after = await whereAmI({'device': session.device});
        }
        result = {
          ...result,
          'content': [
            ...(result['content'] as List? ?? const []),
            {'type': 'text', 'text': 'after: $after'},
          ],
        };
      } on ToolError catch (_) {}
    }
    return result;
  }

  // ------------------------------------------------------------ MCP loop

  void _reply(Object? id, {Object? result, Map<String, Object?>? error}) {
    stdout.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, if (error != null) 'error': error else 'result': result}));
  }

  Future<void> handle(Map<String, Object?> msg) async {
    final id = msg['id'];
    final method = msg['method'];
    final params = (msg['params'] as Map?)?.cast<String, Object?>() ?? const {};
    if (id == null) return; // notification
    switch (method) {
      case 'initialize':
        _reply(
          id,
          result: {
            'protocolVersion': params['protocolVersion'] ?? '2024-11-05',
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'flutter_ai_testing', 'version': serverVersion},
            'instructions': instructions,
          },
        );
      case 'ping':
        _reply(id, result: {});
      case 'tools/list':
        _reply(id, result: {'tools': await listTools()});
      case 'tools/call':
        final name = '${params['name']}';
        try {
          _reply(id, result: await callTool(name, (params['arguments'] as Map?)?.cast<String, Object?>() ?? {}));
        } on ToolError catch (e) {
          _reply(
            id,
            result: {
              'content': [
                {'type': 'text', 'text': e.message},
              ],
              'isError': true,
            },
          );
        } on Object catch (e) {
          _log('$name failed: $e');
          _reply(
            id,
            result: {
              'content': [
                {'type': 'text', 'text': 'internal error: ${e.runtimeType}'},
              ],
              'isError': true,
            },
          );
        }
      default:
        _reply(id, error: {'code': -32601, 'message': 'method not found: $method'});
    }
  }

  /// Serves MCP over stdin/stdout until stdin closes, then stops the apps it
  /// started (attached apps keep running).
  Future<void> serve() async {
    var queue = Future<void>.value();
    await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final Map<String, Object?> msg;
      try {
        msg = (jsonDecode(line) as Map).cast<String, Object?>();
      } catch (_) {
        continue;
      }
      // One request at a time, in order.
      queue = queue.then((_) => handle(msg));
    }
    await queue;
    for (final s in sessions.values.toList()) {
      if (s.app != null) await s.stop();
      s.marionette?.close();
    }
  }
}
