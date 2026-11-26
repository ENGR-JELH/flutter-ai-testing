// Pure Dart (no Flutter): used by the command-line tools in bin/.
import 'dart:io';

/// The app's `ai-testing.conf`: `KEY=value` lines, `#` comments. Read only,
/// never executed. A key may repeat; [all] returns every value, [get] the last.
class AiTestingConf {
  AiTestingConf(this.appDir, this._values);

  /// Reads `ai-testing.conf` in [appDir]; empty when the file is missing.
  factory AiTestingConf.load(Directory appDir) {
    final values = <String, List<String>>{};
    final file = File('${appDir.path}/ai-testing.conf');
    if (file.existsSync()) {
      for (final raw in file.readAsLinesSync()) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue;
        final at = line.indexOf('=');
        values.putIfAbsent(line.substring(0, at).trim(), () => []).add(line.substring(at + 1).trim());
      }
    }
    return AiTestingConf(appDir, values);
  }

  final Directory appDir;
  final Map<String, List<String>> _values;

  bool get exists => File('${appDir.path}/ai-testing.conf').existsSync();

  String get(String key, [String fallback = '']) {
    final list = _values[key];
    return list == null || list.isEmpty || list.last.isEmpty ? fallback : list.last;
  }

  List<String> all(String key) => List.unmodifiable(_values[key] ?? const []);

  List<String> words(String key) => get(key).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  String get appId => get('APP_ID');
  String get target => get('TARGET', 'marionette/main.dart');
  String get uriDir => get('URI_DIR', '.marionette');

  /// `.marionette/<device>.uri`: the connect address of the app on [device].
  File uriFile(String device) => File('${appDir.path}/$uriDir/${safeName(device)}.uri');

  /// `.marionette/<device>.log`: flutter run's output. Never shown to agents.
  File logFile(String device) => File('${appDir.path}/$uriDir/${safeName(device)}.log');
}

String safeName(String device) => device.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

/// The nearest folder at or above [start] with a pubspec.yaml.
Directory? findAppDir([String? start]) {
  var dir = Directory(start ?? Directory.current.path).absolute;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}
