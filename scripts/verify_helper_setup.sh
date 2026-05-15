#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

PROJECT_FILE="$ROOT_DIR/SMCController.xcodeproj/project.pbxproj"
PREPARE_SCRIPT="$ROOT_DIR/SMCHelper/prepare_bundle.sh"
DAEMON_SOURCE="$ROOT_DIR/SMCHelper/main_daemon.c"
DAEMON_CLIENT="$ROOT_DIR/SMCController/Core/Services/DaemonClient.swift"
INSTALLER_SOURCE="$ROOT_DIR/SMCHelper/install_helper.c"

grep -q "Embed SMCHelper Artifacts" "$PROJECT_FILE" \
    || fail "app target does not embed SMCHelper artifacts"

grep -q "../SMCController/Platform/SMCBridge.c" "$PREPARE_SCRIPT" \
    || fail "prepare_bundle.sh does not compile SMCBridge.c from Platform"

if grep -q "../SMCController/SMCBridge" "$PREPARE_SCRIPT" "$DAEMON_SOURCE"; then
    fail "helper build sources still reference the removed SMCBridge path"
fi

grep -q '#include "SMCBridge.h"' "$DAEMON_SOURCE" \
    || fail "main_daemon.c does not include SMCBridge.h through an include path"

grep -q "verifyInstalledDaemonReady" "$DAEMON_CLIENT" \
    || fail "DaemonClient does not perform post-install daemon readiness validation"

grep -q "Installer did not report completion" "$DAEMON_CLIENT" \
    || fail "DaemonClient does not reject incomplete installer output"

grep -q "launchctl load failed" "$INSTALLER_SOURCE" \
    || fail "install_helper.c does not make launchctl load failure explicit"

echo "Helper setup verification passed"
