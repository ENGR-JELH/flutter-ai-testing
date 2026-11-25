#!/usr/bin/env bash
# Installs flutter-ai-testing into a Flutter app, or updates it.
#
#   bash install.sh <app-dir> [--scripts-dir <dir>] [--marionette-dir <dir>]
#
# Always refreshes the installed copies of the tools:
#   <marionette-dir>/ai_testing.dart   (default marionette/)
#   <scripts-dir>/*                    (default scripts/ai-testing/)
# Adds the starting files only when they don't exist yet, so it never
# overwrites what the app has filled in:
#   ai-testing.conf, <marionette-dir>/{main,app_tools,marionette_config}.dart,
#   docs/AUTOMATION-TESTING.md, test_cases/README.md, .mcp.json
#
# The app gets copies, not a package dependency, so its CI never needs access
# to this repository.
set -euo pipefail

kit="$(cd "$(dirname "$0")" && pwd)"
version="$(cat "$kit/VERSION")"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <app-dir> [--scripts-dir <dir>] [--marionette-dir <dir>]" >&2
  exit 2
fi
app="$(cd "$1" && pwd)"
shift
scripts_dir="scripts/ai-testing"
marionette_dir="marionette"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scripts-dir) scripts_dir="$2"; shift 2 ;;
    --marionette-dir) marionette_dir="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$app/pubspec.yaml" ]]; then
  echo "$app has no pubspec.yaml: not a Flutter app" >&2
  exit 2
fi

# Installed copies: always refreshed.
mkdir -p "$app/$marionette_dir" "$app/$scripts_dir"
{
  echo "// Installed from flutter-ai-testing $version. Don't edit this copy: change"
  echo "// lib/flutter_ai_testing.dart in flutter-ai-testing and run install.sh again."
  echo
  cat "$kit/lib/flutter_ai_testing.dart"
} >"$app/$marionette_dir/ai_testing.dart"
echo "updated $marionette_dir/ai_testing.dart"

for f in marionette-run.sh keyscan.py check_test_keys.py gen_test_key_index.py; do
  cp "$kit/scripts/$f" "$app/$scripts_dir/$f"
done
for f in marionette_cli.py vmeval.py; do
  cp "$kit/tools/$f" "$app/$scripts_dir/$f"
done
cp "$kit/mcp/server.py" "$app/$scripts_dir/mcp_server.py"
chmod +x "$app/$scripts_dir/"*.sh "$app/$scripts_dir/"*.py
echo "$version" >"$app/$scripts_dir/AI_TESTING_VERSION"
echo "updated $scripts_dir/ (MCP server, launch script, key checks, helpers)"

# Starting files: only when missing.
add_if_missing() {
  local from="$1" to="$2"
  if [[ -e "$app/$to" ]]; then
    echo "kept    $to (already there)"
  else
    mkdir -p "$(dirname "$app/$to")"
    cp "$kit/templates/$from" "$app/$to"
    echo "added   $to"
  fi
}
add_if_missing ai-testing.conf ai-testing.conf
add_if_missing marionette/main.dart "$marionette_dir/main.dart"
add_if_missing marionette/app_tools.dart "$marionette_dir/app_tools.dart"
add_if_missing marionette/marionette_config.dart "$marionette_dir/marionette_config.dart"
add_if_missing docs/AUTOMATION-TESTING.md docs/AUTOMATION-TESTING.md
add_if_missing test_cases/README.md test_cases/README.md
add_if_missing mcp.json .mcp.json

touch "$app/.gitignore"
if ! grep -qxF ".marionette/" "$app/.gitignore"; then
  printf '\n# Marionette connect addresses written by marionette-run.sh.\n.marionette/\n' >>"$app/.gitignore"
  echo "added   .marionette/ to .gitignore"
fi

echo
if ! grep -qE "^[[:space:]]+marionette_flutter:" "$app/pubspec.yaml"; then
  echo "next: flutter pub add --dev 'marionette_flutter:^0.7.0'"
fi
echo "next: fill in ai-testing.conf and $marionette_dir/app_tools.dart, add keys, then"
echo "      bash $scripts_dir/marionette-run.sh <device-id>"
