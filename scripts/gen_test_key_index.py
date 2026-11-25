#!/usr/bin/env python3
"""Writes the test-key index of a Flutter app (flutter-ai-testing).

For each key it records the file (the page), the control type, the label the
control shows (from the l10n key or literal text nearby) and where it
navigates, when that can be read from the code. Re-run after changing screens:

    python3 <scripts-dir>/gen_test_key_index.py

Output: KEYS_INDEX in ai-testing.conf (default docs/test-keys.md).
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from keyscan import KeyScanner, app_root, setting  # noqa: E402

ICON = re.compile(r"\b(Icon|SvgPicture|Image)\(|\w+\.(svg|png)['\"]|Icons\.")
WIDGET = re.compile(r"\b([A-Z][A-Za-z]+)\(")
SKIP_WIDGETS = {"ValueKey", "Key", "Text", "Padding", "SizedBox", "Center", "Container",
                "Row", "Column", "Align", "Expanded", "Flexible", "Positioned", "Stack",
                "Semantics", "Scaffold", "Builder", "Opacity", "ClipRRect", "Transform",
                "KeyedSubtree", "Image", "Icon", "SvgPicture", "Visibility", "AnimatedContainer",
                "AnimatedOpacity", "Divider", "Wrap", "Spacer", "Tooltip"}
LABEL_PATTERNS = [
    re.compile(r"AppLocalizations\.of\(\s*context\s*\)!\.(\w+)"),
    re.compile(r"\bloc\.(\w+)"),
    re.compile(r"\bl10n\.(\w+)"),
    re.compile(r"label:\s*'([^']{2,60})'"),
    re.compile(r"Text\(\s*'([^']{2,60})'"),
    re.compile(r"hintText:\s*'([^']{2,60})'"),
]
# context.goNamed(AppRoutes.x.name), router.push(Routes.x), pushNamed('x') ...
NAV_ROUTE = re.compile(
    r"(?:pushNamed|goNamed|pushReplacementNamed|push|go)\(\s*(?:context\s*,\s*)?"
    r"(?:[A-Z]\w*Routes?\.(\w+)|'([\w/-]+)')"
)
# Navigator / helper pushes of a widget: ...push(..., FooScreen(...))
NAV_SCREEN = re.compile(r"(?:push\w*|navigate\w*)\([^;]{0,200}?\b([A-Z]\w*(?:Screen|Page))\(")


def humanize(raw):
    text = raw.replace("_", " ").strip()
    return text[:1].upper() + text[1:] if text else text


def control_type(lines, idx):
    for j in range(idx, max(idx - 15, -1), -1):
        found = [m.group(1) for m in WIDGET.finditer(lines[j]) if m.group(1) not in SKIP_WIDGETS]
        if found:
            return found[-1]
    return "widget"


def label_for(lines, idx):
    window = "\n".join(lines[idx:idx + 30])
    for pattern in LABEL_PATTERNS:
        m = pattern.search(window)
        if m:
            return humanize(m.group(1))
    if ICON.search(window):
        return "icon"
    return "—"


def target_for(lines, idx, tab_switch):
    window = "\n".join(lines[idx:idx + 30])
    m = NAV_ROUTE.search(window)
    if m:
        return f"opens `{m.group(1) or m.group(2)}`"
    m = NAV_SCREEN.search(window)
    if m:
        return f"opens `{m.group(1)}`"
    if tab_switch and tab_switch.search(window):
        return "switches tab"
    return ""


def element(key):
    words = re.sub(r"<[^>]*>|\(.*\)", "", key).replace("_", " ").replace("$", "").strip()
    return words[:1].upper() + words[1:]


def anchor(title):
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")


def main():
    root = app_root()
    scanner = KeyScanner(root)
    out = root / setting(scanner.conf, "KEYS_INDEX", "docs/test-keys.md")
    guide = setting(scanner.conf, "KEYS_GUIDE", "AUTOMATION-TESTING.md")
    tab_name = setting(scanner.conf, "KEYS_TAB_SWITCH")
    tab_switch = re.compile(re.escape(tab_name) + r"\(") if tab_name else None
    suffix = setting(scanner.conf, "SCREEN_KEY_SUFFIX", "_screen")
    notes = scanner.conf.get("KEYS_NOTE", [])

    pages = []
    for path in scanner.files():
        lines = path.read_text(errors="ignore").splitlines()
        rows = [(key, i + 1, control_type(lines, i), label_for(lines, i), target_for(lines, i, tab_switch))
                for key, i in scanner.keys_in(path)]
        if rows:
            roots = [key for key, *_ in rows if key.endswith(suffix)]
            pages.append((str(path.relative_to(scanner.lib)), roots[0] if roots else "", rows))

    total = sum(len(rows) for _, _, rows in pages)
    md = [
        "# Test keys by page",
        "",
        "Every test key in the app, grouped by the page (file) it is on. Use it to write",
        "automated test steps: find the page, pick the key, and read what the control does.",
        "",
        "- **Element**: what the key names, read from the key itself.",
        "- **Widget**: the widget type that carries the key.",
        "- **Shows**: the label the control displays, from the app's translations or its text;",
        "  `icon` for icon-only controls, `—` when the code builds it from a variable.",
        "- **Does**: where the control navigates, when the code makes that visible.",
        "- Keys with `$` or `<...>` are built at run time (a record id, an index, a tab name).",
        *[f"- {note}" for note in notes],
        "",
        f"How to use it: [{guide}]({guide}) explains setup and how to drive the app.",
        "",
        f"Total keys: **{total}** on **{len(pages)}** pages. Generated by",
        "`gen_test_key_index.py` (flutter-ai-testing). Do not edit this file by hand.",
        "",
        "## Pages",
        "",
    ]
    md += [f"- [`{title}`](#{anchor(title)}) ({len(rows)})" for title, _, rows in pages]
    md.append("")
    for title, page_root, rows in pages:
        md += [f"## `{title}`", ""]
        if page_root:
            md += [f"Page check: `{page_root}` (the screen root).", ""]
        md += ["| Key | Element | Widget | Shows | Does | Line |", "|---|---|---|---|---|---|"]
        md += [f"| `{key}` | {element(key)} | {ctrl} | {label} | {target} | {line} |"
               for key, line, ctrl, label, target in rows]
        md.append("")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(md))
    print(f"wrote {out.relative_to(root)} ({total} keys, {len(pages)} pages)")


if __name__ == "__main__":
    sys.exit(main())
