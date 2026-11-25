#!/usr/bin/env bash
# Runs a Flutter app through its Marionette entrypoint and saves the address an
# AI agent connects to. Part of flutter-ai-testing; settings come from the app's
# ai-testing.conf (see templates/ai-testing.conf).
#
#   bash <scripts-dir>/marionette-run.sh <device-id> [extra flutter run args...]
#
# Prints MARIONETTE_URI=ws://... and saves it to <URI_DIR>/<device-id>.uri.
# Find device ids with `flutter devices`. Stop with Ctrl+C or `q`.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <device-id> [flutter run args...]" >&2
  exit 2
fi
device="$1"
shift

# The app root is AI_TESTING_APP_DIR when set (the MCP server sets it),
# otherwise the nearest folder above this script with a pubspec.yaml.
dir="$(cd "${AI_TESTING_APP_DIR:-$(dirname "$0")}" && pwd)"
while [[ "$dir" != "/" && ! -f "$dir/pubspec.yaml" ]]; do dir="$(dirname "$dir")"; done
if [[ ! -f "$dir/pubspec.yaml" ]]; then
  echo "no pubspec.yaml above $0" >&2
  exit 2
fi
cd "$dir"

conf="ai-testing.conf"
if [[ ! -f "$conf" ]]; then
  echo "missing $dir/$conf (copy templates/ai-testing.conf from flutter-ai-testing)" >&2
  exit 2
fi
# KEY=value lines only; the file is read, never executed.
setting() {
  local line
  line="$(grep -E "^$1=" "$conf" | tail -1 || true)"
  printf '%s' "${line#*=}"
}

app_id="$(setting APP_ID)"
target="$(setting TARGET)"
target="${target:-marionette/main.dart}"
define_name="$(setting DEFINE_NAME)"
define_default="$(setting DEFINE_DEFAULT)"
define_must_contain="$(setting DEFINE_MUST_CONTAIN)"
android_permissions="$(setting ANDROID_PERMISSIONS)"
ios_permissions="$(setting IOS_PERMISSIONS)"
uri_dir="$(setting URI_DIR)"
uri_dir="${uri_dir:-.marionette}"
flutter_version="$(setting FLUTTER_VERSION)"

if [[ -z "$app_id" ]]; then
  echo "APP_ID is not set in $conf" >&2
  exit 2
fi

defines=()
if [[ -n "$define_name" ]]; then
  # The environment can override the default (for example another test host),
  # but the value must still contain DEFINE_MUST_CONTAIN.
  value="${!define_name:-$define_default}"
  if [[ -n "$define_must_contain" && "$value" != *"$define_must_contain"* ]]; then
    echo "refusing: $define_name must contain '$define_must_contain' for agent testing" >&2
    exit 2
  fi
  defines=(--dart-define="$define_name=$value")
fi

# fvm only when the app pins a version: outside an fvm project `fvm flutter`
# prints nothing, so the connect address would never be seen.
if [[ -n "${FLUTTER_BIN:-}" ]]; then
  flutter=("$FLUTTER_BIN")
elif [[ -f .fvmrc ]] && command -v fvm >/dev/null 2>&1 && fvm flutter --version >/dev/null 2>&1; then
  flutter=(fvm flutter)
elif [[ -n "$flutter_version" && -x "$HOME/fvm/versions/$flutter_version/bin/flutter" ]]; then
  flutter=("$HOME/fvm/versions/$flutter_version/bin/flutter")
elif command -v flutter >/dev/null 2>&1; then
  flutter=(flutter)
else
  newest="$(ls -d "$HOME"/fvm/versions/[0-9]*/bin/flutter 2>/dev/null | sort -V | tail -1)"
  if [[ -z "$newest" ]]; then
    echo "flutter not found: put it on PATH, set FLUTTER_BIN or FLUTTER_VERSION" >&2
    exit 2
  fi
  flutter=("$newest")
fi
echo "using ${flutter[*]}"

adb="$(command -v adb || echo "${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb")"

# Marionette can't see or tap OS permission dialogs, so grant them up front.
# MARIONETTE_GRANT=0 keeps the dialogs, for a case that tests the prompts
# themselves (tap them with Maestro).
granting=1
[[ "${MARIONETTE_GRANT:-1}" == "0" ]] && granting=0
platform=physical
if "$adb" devices 2>/dev/null | grep -q "^${device}[[:space:]]"; then
  platform=android
elif command -v xcrun >/dev/null 2>&1 && xcrun simctl list devices booted 2>/dev/null | grep -q "$device"; then
  platform=ios-sim
fi

# iOS: grant BEFORE launch. Changing a permission ends the running app, which
# would also end this debug session. Grants by bundle id work before the first
# install too. The simulator can't pre-grant notifications: tap "Allow" with
# Maestro the first time.
if [[ $granting == 1 && $platform == ios-sim && -n "$ios_permissions" ]]; then
  for s in $ios_permissions; do
    xcrun simctl privacy "$device" grant "$s" "$app_id" >/dev/null 2>&1 || true
  done
  echo "granted iOS simulator permissions: $ios_permissions"
fi
if [[ $granting == 1 && $platform == physical ]]; then
  echo "physical device: grant permissions by hand if the app asks"
fi

# Android: pm grant needs the app installed, so it runs once flutter run has
# installed and started it. Granting doesn't restart the app.
grant_android() {
  [[ $granting == 1 && $platform == android && -n "$android_permissions" ]] || return 0
  for p in $android_permissions; do
    "$adb" -s "$device" shell pm grant "$app_id" "android.permission.$p" >/dev/null 2>&1 || true
  done
  echo "granted Android permissions: $android_permissions"
}

mkdir -p "$uri_dir"
uri_file="$uri_dir/${device//[^A-Za-z0-9_.-]/_}.uri"
rm -f "$uri_file"

# Keep stdin attached so `r`, `R` and `q` still work in the terminal.
"${flutter[@]}" run -t "$target" -d "$device" ${defines[@]+"${defines[@]}"} "$@" 2>&1 |
  while IFS= read -r line; do
    printf '%s\n' "$line"
    if [[ "$line" == *"Dart VM Service"* &&
      "$line" =~ (http://127\.0\.0\.1:[0-9]+/[^/[:space:]]+/) ]]; then
      ws="${BASH_REMATCH[1]/http:/ws:}ws"
      printf '%s\n' "$ws" >"$uri_file"
      printf 'MARIONETTE_URI=%s  (saved to %s)\n' "$ws" "$uri_file"
      grant_android
    fi
  done
