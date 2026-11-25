"""Shared by check_test_keys.py and gen_test_key_index.py (flutter-ai-testing).

Finds every test key in a Flutter app's source:
- ValueKey('literal') and ValueKey("literal"), also split over several lines;
- ValueKey(<KeysClass>.constant), resolved from the constants file;
- ValueKey(<KeysClass>.method(...)), shown with a placeholder from KEYS_DYNAMIC;
- 'key': 'literal' map entries, applied later with ValueKey(item['key']).

Settings come from the app's ai-testing.conf (KEY=value lines, read only).
"""
import pathlib
import re
import sys


def app_root(start=None):
    """Nearest folder with a pubspec.yaml, from the current directory up."""
    here = pathlib.Path(start or pathlib.Path.cwd()).resolve()
    for folder in [here, *here.parents]:
        if (folder / "pubspec.yaml").is_file():
            return folder
    sys.exit("no pubspec.yaml found: run this from inside a Flutter app")


def read_conf(root):
    conf = {}
    path = root / "ai-testing.conf"
    if not path.is_file():
        return conf
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        conf.setdefault(name.strip(), []).append(value.strip())
    return conf


def setting(conf, name, default=""):
    values = conf.get(name)
    return values[-1] if values else default


class KeyScanner:
    def __init__(self, root):
        self.root = root
        self.conf = read_conf(root)
        self.lib = root / setting(self.conf, "KEYS_LIB", "lib")
        self.keys_class = setting(self.conf, "KEYS_CLASS", "TestKeys")
        constants_file = setting(self.conf, "KEYS_CONSTANTS")
        self.constants = {}
        if constants_file and (root / constants_file).is_file():
            text = (root / constants_file).read_text()
            self.constants = dict(re.findall(r"static const String (\w+) = '([^']*)';", text))
        # KEYS_DYNAMIC=navTab=nav_tab_<tab>: how to show TestKeys.navTab(...).
        self.dynamic = {}
        for entry in self.conf.get("KEYS_DYNAMIC", []):
            if "=" in entry:
                method, placeholder = entry.split("=", 1)
                self.dynamic[method.strip()] = placeholder.strip()
        cls = re.escape(self.keys_class)
        self.pattern = re.compile(
            r"ValueKey\(\s*(?:'([^']*)'|\"([^\"]*)\"|" + cls + r"\.(\w+)(\(([^)]*)\))?)\s*,?\s*\)"
            r"|'key':\s*'([a-z0-9_$]+)'"
        )

    def key_text(self, m):
        single, double, member, call, _args, mapped = m.groups()
        if mapped is not None:
            return mapped
        if single is not None:
            return single
        if double is not None:
            return double
        if call is not None:
            return self.dynamic.get(member, f"{member}(...)")
        return self.constants.get(member, f"{self.keys_class}.{member}")

    def files(self):
        return sorted(self.lib.rglob("*.dart"))

    def keys_in(self, path):
        """Yields (key, 0-based line index) for one file."""
        text = path.read_text(errors="ignore")
        for m in self.pattern.finditer(text):
            yield self.key_text(m), text.count("\n", 0, m.start())
