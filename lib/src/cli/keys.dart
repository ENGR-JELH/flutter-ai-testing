// Pure Dart (no Flutter): finds, checks and indexes an app's test keys.
import 'dart:io';

import 'conf.dart';

/// One key found in the source.
class FoundKey {
  FoundKey(this.key, this.line);
  final String key;

  /// 0-based line index.
  final int line;
}

/// Finds every test key in an app:
/// - `ValueKey('x')` / `ValueKey("x")`, also split over several lines;
/// - `ValueKey(<KeysClass>.constant)`, resolved from the constants file;
/// - `ValueKey(<KeysClass>.method(...))`, shown with a KEYS_DYNAMIC placeholder;
/// - `'key': 'x'` map entries, applied later with `ValueKey(item['key'])`.
class KeyScanner {
  KeyScanner(this.conf) {
    keysClass = conf.get('KEYS_CLASS', 'TestKeys');
    final constantsFile = conf.get('KEYS_CONSTANTS');
    if (constantsFile.isNotEmpty) {
      final f = File('${conf.appDir.path}/$constantsFile');
      if (f.existsSync()) {
        for (final m in RegExp(r"static const String (\w+) = '([^']*)';").allMatches(f.readAsStringSync())) {
          constants[m.group(1)!] = m.group(2)!;
        }
      }
    }
    for (final entry in conf.all('KEYS_DYNAMIC')) {
      final at = entry.indexOf('=');
      if (at > 0) dynamic_[entry.substring(0, at).trim()] = entry.substring(at + 1).trim();
    }
    final cls = RegExp.escape(keysClass);
    pattern = RegExp(
      "ValueKey\\(\\s*(?:'([^']*)'|\"([^\"]*)\"|$cls\\.(\\w+)(\\(([^)]*)\\))?)\\s*,?\\s*\\)"
      r"|'key':\s*'([a-z0-9_$]+)'",
    );
  }

  final AiTestingConf conf;
  late final String keysClass;
  final constants = <String, String>{};
  final dynamic_ = <String, String>{};
  late final RegExp pattern;

  Directory get lib => Directory('${conf.appDir.path}/${conf.get('KEYS_LIB', 'lib')}');

  List<File> files() {
    if (!lib.existsSync()) return const [];
    return lib.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  String _text(RegExpMatch m) {
    if (m.group(6) != null) return m.group(6)!;
    if (m.group(1) != null) return m.group(1)!;
    if (m.group(2) != null) return m.group(2)!;
    final member = m.group(3)!;
    if (m.group(4) != null) return dynamic_[member] ?? '$member(...)';
    return constants[member] ?? '$keysClass.$member';
  }

  List<FoundKey> keysIn(File file) {
    final text = file.readAsStringSync();
    return [
      for (final m in pattern.allMatches(text)) FoundKey(_text(m), '\n'.allMatches(text.substring(0, m.start)).length),
    ];
  }

  String relative(File f, Directory base) => f.path.substring(base.path.length + 1);
}

/// Result of [checkKeys].
class KeyCheck {
  KeyCheck(this.total, this.problems, this.lines);
  final int total;
  final int problems;
  final List<String> lines;
  bool get ok => problems == 0;
}

/// Fails on keys that look like contact data (keys show up in agent output
/// and docs). Warns on a literal key used more than once in one file, which is
/// fine only in mutually exclusive branches.
KeyCheck checkKeys(AiTestingConf conf) {
  final scanner = KeyScanner(conf);
  final contact = RegExp(r'@|\d{3}[-. ]?\d{3}[-. ]?\d{4}');
  final out = <String>[];
  var total = 0, problems = 0;
  for (final file in scanner.files()) {
    final keys = scanner.keysIn(file);
    total += keys.length;
    final rel = scanner.relative(file, conf.appDir);
    final counts = <String, List<int>>{};
    for (final k in keys) {
      counts.putIfAbsent(k.key, () => []).add(k.line + 1);
    }
    counts.forEach((key, lines) {
      if (lines.length > 1 && !key.contains(r'$') && !key.contains('(') && !key.contains('<')) {
        out.add("WARN  $rel: '$key' used ${lines.length}x at lines $lines (check the branches are exclusive)");
      }
    });
    for (final k in keys) {
      if (contact.hasMatch(k.key)) {
        out.add('FAIL  $rel:${k.line + 1}: key looks like contact data');
        problems++;
      }
    }
  }
  out.add('keys: $total, problems: $problems');
  return KeyCheck(total, problems, out);
}

const _skipWidgets = {
  'ValueKey', 'Key', 'Text', 'Padding', 'SizedBox', 'Center', 'Container', 'Row', 'Column', 'Align', //
  'Expanded', 'Flexible', 'Positioned', 'Stack', 'Semantics', 'Scaffold', 'Builder', 'Opacity', 'ClipRRect',
  'Transform', 'KeyedSubtree', 'Image', 'Icon', 'SvgPicture', 'Visibility', 'AnimatedContainer',
  'AnimatedOpacity', 'Divider', 'Wrap', 'Spacer', 'Tooltip',
};
final _widget = RegExp(r'\b([A-Z][A-Za-z]+)\(');
final _icon = RegExp(r'''\b(Icon|SvgPicture|Image)\(|\w+\.(svg|png)['"]|Icons\.''');
final _labels = [
  RegExp(r'AppLocalizations\.of\(\s*context\s*\)!\.(\w+)'),
  RegExp(r'\bloc\.(\w+)'),
  RegExp(r'\bl10n\.(\w+)'),
  RegExp(r"label:\s*'([^']{2,60})'"),
  RegExp(r"Text\(\s*'([^']{2,60})'"),
  RegExp(r"hintText:\s*'([^']{2,60})'"),
];
final _navRoute = RegExp(
  r"(?:pushNamed|goNamed|pushReplacementNamed|push|go)\(\s*(?:context\s*,\s*)?(?:[A-Z]\w*Routes?\.(\w+)|'([\w/-]+)')",
);
final _navScreen = RegExp(r'(?:push\w*|navigate\w*)\([^;]{0,200}?\b([A-Z]\w*(?:Screen|Page))\(');

String _humanize(String raw) {
  final t = raw.replaceAll('_', ' ').trim();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

/// Writes the key index (KEYS_INDEX, default docs/test-keys.md) and returns
/// its path relative to the app.
({String path, int keys, int pages}) writeKeyIndex(AiTestingConf conf) {
  final scanner = KeyScanner(conf);
  final outPath = conf.get('KEYS_INDEX', 'docs/test-keys.md');
  final guide = conf.get('KEYS_GUIDE', 'AUTOMATION-TESTING.md');
  final tabName = conf.get('KEYS_TAB_SWITCH');
  final tabSwitch = tabName.isEmpty ? null : RegExp('${RegExp.escape(tabName)}\\(');
  final suffix = conf.get('SCREEN_KEY_SUFFIX', '_screen');

  String control(List<String> lines, int i) {
    for (var j = i; j > i - 15 && j >= 0; j--) {
      final found = _widget.allMatches(lines[j]).map((m) => m.group(1)!).where((w) => !_skipWidgets.contains(w));
      if (found.isNotEmpty) return found.last;
    }
    return 'widget';
  }

  String window(List<String> lines, int i) => lines.sublist(i, (i + 30).clamp(0, lines.length)).join('\n');

  String label(List<String> lines, int i) {
    final w = window(lines, i);
    for (final p in _labels) {
      final m = p.firstMatch(w);
      if (m != null) return _humanize(m.group(1)!);
    }
    return _icon.hasMatch(w) ? 'icon' : '—';
  }

  String target(List<String> lines, int i) {
    final w = window(lines, i);
    final r = _navRoute.firstMatch(w);
    if (r != null) return 'opens `${r.group(1) ?? r.group(2)}`';
    final s = _navScreen.firstMatch(w);
    if (s != null) return 'opens `${s.group(1)}`';
    return tabSwitch != null && tabSwitch.hasMatch(w) ? 'switches tab' : '';
  }

  String element(String key) {
    final words = key.replaceAll(RegExp(r'<[^>]*>|\(.*\)'), '').replaceAll('_', ' ').replaceAll(r'$', '').trim();
    return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
  }

  String anchor(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

  final pages = <(String, String, List<String>)>[];
  var total = 0;
  for (final file in scanner.files()) {
    final keys = scanner.keysIn(file);
    if (keys.isEmpty) continue;
    final lines = file.readAsLinesSync();
    final rows = [
      for (final k in keys)
        '| `${k.key}` | ${element(k.key)} | ${control(lines, k.line)} | ${label(lines, k.line)} | ${target(lines, k.line)} | ${k.line + 1} |',
    ];
    total += rows.length;
    final root = keys.map((k) => k.key).where((k) => k.endsWith(suffix)).firstOrNull ?? '';
    pages.add((scanner.relative(file, scanner.lib), root, rows));
  }

  final md = <String>[
    '# Test keys by page',
    '',
    'Every test key in the app, grouped by the page (file) it is on. Use it to write',
    'automated test steps: find the page, pick the key, and read what the control does.',
    '',
    '- **Element**: what the key names, read from the key itself.',
    '- **Widget**: the widget type that carries the key.',
    "- **Shows**: the label the control displays, from the app's translations or its text;",
    '  `icon` for icon-only controls, `—` when the code builds it from a variable.',
    '- **Does**: where the control navigates, when the code makes that visible.',
    r'- Keys with `$` or `<...>` are built at run time (a record id, an index, a tab name).',
    for (final note in conf.all('KEYS_NOTE')) '- $note',
    '',
    'How to use it: [$guide]($guide) explains setup and how to drive the app.',
    '',
    'Total keys: **$total** on **${pages.length}** pages. Generated by',
    '`dart run flutter_ai_testing:keys index`. Do not edit this file by hand.',
    '',
    '## Pages',
    '',
    for (final (title, _, rows) in pages) '- [`$title`](#${anchor(title)}) (${rows.length})',
    '',
  ];
  for (final (title, root, rows) in pages) {
    md
      ..add('## `$title`')
      ..add('');
    if (root.isNotEmpty) {
      md
        ..add('Page check: `$root` (the screen root).')
        ..add('');
    }
    md
      ..add('| Key | Element | Widget | Shows | Does | Line |')
      ..add('|---|---|---|---|---|---|')
      ..addAll(rows)
      ..add('');
  }
  final out = File('${conf.appDir.path}/$outPath')..parent.createSync(recursive: true);
  out.writeAsStringSync(md.join('\n'));
  return (path: outPath, keys: total, pages: pages.length);
}
