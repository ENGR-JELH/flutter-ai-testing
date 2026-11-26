// Pure Dart (no Flutter): starts an app through its Marionette entrypoint.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'conf.dart';

class LaunchError implements Exception {
  LaunchError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An app started with `flutter run` on one device.
class RunningApp {
  RunningApp._(this.device, this.conf, this.process);

  final String device;
  final AiTestingConf conf;
  final Process process;
  final _uri = Completer<String>();
  int? exitCode;

  /// Completes with the `ws://` address once flutter run prints it.
  Future<String> get uri => _uri.future;
  bool get hasUri => _uri.isCompleted;
  bool get exited => exitCode != null;

  /// Quits flutter run (which stops the app), then ends anything left.
  Future<void> stop() async {
    if (!exited) {
      try {
        process.stdin.write('q');
        await process.stdin.flush();
      } catch (_) {}
      await process.exitCode.timeout(const Duration(seconds: 15), onTimeout: () => -1);
    }
    await killTree(process.pid);
  }
}

/// Where the app's tools run: a phone, an emulator or a simulator.
enum DeviceKind { android, iosSimulator, physical }

class Launcher {
  Launcher(this.conf);

  final AiTestingConf conf;

  Directory get appDir => conf.appDir;

  /// Flutter to run: FLUTTER_BIN, fvm when the app pins a version (.fvmrc),
  /// FLUTTER_VERSION from the conf, flutter on PATH, or the newest fvm SDK.
  /// Not `fvm flutter` outside an fvm project: it prints nothing there.
  List<String> flutterCommand() {
    final env = Platform.environment;
    if ((env['FLUTTER_BIN'] ?? '').isNotEmpty) return [env['FLUTTER_BIN']!];
    final fvm = which('fvm');
    if (File('${appDir.path}/.fvmrc').existsSync() && fvm != null) return [fvm, 'flutter'];
    final version = conf.get('FLUTTER_VERSION');
    if (version.isNotEmpty) {
      for (final root in fvmVersionRoots()) {
        final pinned = File('${root.path}/$version/bin/$flutterExe');
        if (pinned.existsSync()) return [pinned.path];
      }
    }
    final onPath = which('flutter');
    if (onPath != null) return [onPath];
    final newest = newestFvmBin();
    if (newest != null) return ['$newest/$flutterExe'];
    throw LaunchError('flutter not found: put it on PATH, or set FLUTTER_BIN or FLUTTER_VERSION');
  }

  /// adb on PATH, else in ANDROID_HOME / ANDROID_SDK_ROOT, else in the
  /// Android Studio default SDK folder for this OS.
  String get adb {
    final onPath = which('adb');
    if (onPath != null) return onPath;
    final env = Platform.environment;
    final sdk =
        env['ANDROID_HOME'] ??
        env['ANDROID_SDK_ROOT'] ??
        (Platform.isWindows
            ? '${env['LOCALAPPDATA']}\\Android\\Sdk'
            : Platform.isMacOS
            ? '$homeDir/Library/Android/sdk'
            : '$homeDir/Android/Sdk');
    return '$sdk/platform-tools/adb${Platform.isWindows ? '.exe' : ''}';
  }

  Future<DeviceKind> platformOf(String device) async {
    try {
      final r = await Process.run(adb, ['devices']);
      if (LineSplitter.split('${r.stdout}').any((l) => l.split(RegExp(r'\s+')).first == device)) {
        return DeviceKind.android;
      }
    } catch (_) {}
    if (Platform.isMacOS) {
      try {
        final r = await Process.run('xcrun', ['simctl', 'list', 'devices', 'booted']);
        if ('${r.stdout}'.contains(device)) return DeviceKind.iosSimulator;
      } catch (_) {}
    }
    return DeviceKind.physical;
  }

  /// The `--dart-define` the conf asks for, after its safety check.
  List<String> defines() {
    final name = conf.get('DEFINE_NAME');
    if (name.isEmpty) return const [];
    final value = Platform.environment[name] ?? conf.get('DEFINE_DEFAULT');
    final mustContain = conf.get('DEFINE_MUST_CONTAIN');
    if (mustContain.isNotEmpty && !value.contains(mustContain)) {
      throw LaunchError("refusing: $name must contain '$mustContain' for agent testing");
    }
    return ['--dart-define=$name=$value'];
  }

  /// Starts the app. [onLine] receives every output line (for a terminal;
  /// the MCP server only writes them to the log file). Permissions are granted
  /// unless MARIONETTE_GRANT=0: iOS simulator before launch (a change ends a
  /// running app), Android after install (pm grant needs the app).
  Future<RunningApp> start(
    String device, {
    List<String> extraArgs = const [],
    void Function(String line)? onLine,
  }) async {
    if (!conf.exists) {
      throw LaunchError('${appDir.path} has no ai-testing.conf: run `dart run flutter_ai_testing:init`');
    }
    if (conf.appId.isEmpty) throw LaunchError('APP_ID is not set in ai-testing.conf');
    final target = File('${appDir.path}/${conf.target}');
    if (!target.existsSync()) throw LaunchError('Marionette entrypoint ${conf.target} not found');
    final defs = defines();
    final command = flutterCommand();
    final granting = Platform.environment['MARIONETTE_GRANT'] != '0';
    final platform = await platformOf(device);

    void note(String line) => onLine?.call(line);

    if (granting && platform == DeviceKind.iosSimulator) {
      final services = conf.words('IOS_PERMISSIONS');
      for (final s in services) {
        await Process.run('xcrun', ['simctl', 'privacy', device, 'grant', s, conf.appId]);
      }
      if (services.isNotEmpty) note('granted iOS simulator permissions: ${services.join(' ')}');
    } else if (granting && platform == DeviceKind.physical) {
      note('physical device: grant permissions by hand if the app asks');
    }

    final uriFile = conf.uriFile(device)..parent.createSync(recursive: true);
    if (uriFile.existsSync()) uriFile.deleteSync();
    final log = conf.logFile(device).openWrite();
    log.writeln('using ${command.join(' ')}');

    final process = await Process.start(runInShell: needsShell(command.first), command.first, [
      ...command.skip(1),
      'run',
      '-t',
      conf.target,
      '-d',
      device,
      ...defs,
      ...extraArgs,
    ], workingDirectory: appDir.path);
    final app = RunningApp._(device, conf, process);
    final vmLine = RegExp(r'(http://127\.0\.0\.1:\d+/[^/\s]+/)');

    Future<void> handle(String line) async {
      log.writeln(line);
      onLine?.call(line);
      if (!app.hasUri && line.contains('Dart VM Service')) {
        final m = vmLine.firstMatch(line);
        if (m != null) {
          final ws = '${m.group(1)!.replaceFirst('http:', 'ws:')}ws';
          uriFile.writeAsStringSync('$ws\n');
          note('MARIONETTE_URI=$ws  (saved to ${uriFile.path})');
          if (granting && platform == DeviceKind.android) {
            final perms = conf.words('ANDROID_PERMISSIONS');
            for (final p in perms) {
              await Process.run(adb, ['-s', device, 'shell', 'pm', 'grant', conf.appId, 'android.permission.$p']);
            }
            if (perms.isNotEmpty) note('granted Android permissions: ${perms.join(' ')}');
          }
          app._uri.complete(ws);
        }
      }
    }

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(handle);
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(handle);
    unawaited(
      process.exitCode.then((code) async {
        app.exitCode = code;
        await log.flush();
        await log.close();
        if (!app.hasUri) app._uri.completeError(LaunchError('flutter run exited ($code) before the app started'));
      }),
    );
    return app;
  }
}

/// Known problems recognised in a run log. Only these fixed messages are ever
/// shown to an agent, never the log itself: it can contain personal data.
String? knownProblem(File log) {
  if (!log.existsSync()) return null;
  final text = log.readAsStringSync();
  const problems = <String, String>{
    r'Gradle task \S+ failed|BUILD FAILED': 'Android build failed: run the app once by hand to see the error',
    r'Error \(Xcode\)|Could not build the application': 'iOS build failed: run the app once by hand to see the error',
    r'No supported devices|No devices found': 'device not found',
    r'Lost connection to device': 'lost connection to the device (app closed or crashed)',
    r'Target file .* not found': 'Marionette entrypoint not found (TARGET in ai-testing.conf)',
  };
  for (final e in problems.entries) {
    if (RegExp(e.key).hasMatch(text)) return e.value;
  }
  return null;
}

/// The user's home folder (HOME, or USERPROFILE on Windows).
String get homeDir => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

/// `flutter.bat` on Windows, `flutter` elsewhere.
String get flutterExe => Platform.isWindows ? 'flutter.bat' : 'flutter';

/// Windows starts `.bat` / `.cmd` files only through the shell.
bool needsShell(String executable) =>
    Platform.isWindows && RegExp(r'\.(bat|cmd)$', caseSensitive: false).hasMatch(executable);

/// The executable on PATH, or null. On Windows also tries the PATHEXT
/// extensions (`flutter.bat`, `adb.exe`, ...).
String? which(String name) {
  final env = Platform.environment;
  final exts = Platform.isWindows
      ? ['', ...(env['PATHEXT'] ?? '.EXE;.BAT;.CMD').split(';').where((e) => e.isNotEmpty)]
      : [''];
  for (final dir in (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    for (final ext in exts) {
      final f = File('$dir${Platform.pathSeparator}$name$ext');
      if (f.existsSync()) return f.path;
    }
  }
  return null;
}

/// Folders fvm keeps Flutter versions in: `~/fvm/versions`, and on Windows
/// also `%LOCALAPPDATA%\fvm\versions`. FVM_CACHE_PATH first when set.
List<Directory> fvmVersionRoots() {
  final env = Platform.environment;
  return [
    if ((env['FVM_CACHE_PATH'] ?? '').isNotEmpty) Directory('${env['FVM_CACHE_PATH']}/versions'),
    Directory('$homeDir/fvm/versions'),
    if (Platform.isWindows && env['LOCALAPPDATA'] != null) Directory('${env['LOCALAPPDATA']}/fvm/versions'),
  ].where((d) => d.existsSync()).toList();
}

/// The bin folder of the highest numbered fvm Flutter (channels like `stable` last).
String? newestFvmBin() {
  List<int> nums(String name) => name.split('.').map(int.tryParse).whereType<int>().toList();
  final versions =
      [
        for (final root in fvmVersionRoots()) ...root.listSync().whereType<Directory>(),
      ].where((d) => File('${d.path}/bin/$flutterExe').existsSync()).toList()..sort((a, b) {
        final x = nums(a.uri.pathSegments.where((s) => s.isNotEmpty).last);
        final y = nums(b.uri.pathSegments.where((s) => s.isNotEmpty).last);
        for (var i = 0; i < x.length && i < y.length; i++) {
          if (x[i] != y[i]) return x[i].compareTo(y[i]);
        }
        return x.length.compareTo(y.length);
      });
  return versions.isEmpty ? null : '${versions.last.path}/bin';
}

/// Ends [pid] and every process it started (flutter run starts several).
Future<void> killTree(int pid) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
    return;
  }
  try {
    final r = await Process.run('pgrep', ['-P', '$pid']);
    for (final child in LineSplitter.split('${r.stdout}')) {
      final c = int.tryParse(child.trim());
      if (c != null) await killTree(c);
    }
  } catch (_) {}
  Process.killPid(pid);
}
