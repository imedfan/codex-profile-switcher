#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/.build/local-app/QuotaPilot Test.app}"
APP_BUNDLE="$LOCAL_APP_BUNDLE" \
APP_DISPLAY_NAME="QuotaPilot Test" \
BUNDLE_ID="com.4lau.codex-profile-switcher.local" \
HELPER_BUNDLE_ID="com.4lau.codex-profile-switcher.local" \
CODEX_PROFILE_LOCAL_BUILD=1 \
CODEX_PROFILE_REQUIRE_SIGNING=0 \
APP_IDENTITY='' \
"$ROOT_DIR/Scripts/package_app.sh"

info_plist="$LOCAL_APP_BUNDLE/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")" == \
    'com.4lau.codex-profile-switcher.local' ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$info_plist")" == false ]]
if /usr/libexec/PlistBuddy -c 'Print :LSEnvironment' "$info_plist" >/dev/null 2>&1; then
    printf 'Local app unexpectedly contains an environment override.\n' >&2
    exit 1
fi
