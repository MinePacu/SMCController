#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

PROJECT_FILE="$ROOT_DIR/SMCController.xcodeproj/project.pbxproj"
DAEMON_SOURCE="$ROOT_DIR/SMCHelper/main_daemon.c"
DAEMON_CLIENT="$ROOT_DIR/SMCController/Core/Services/DaemonClient.swift"
INSTALLER_SOURCE="$ROOT_DIR/SMCHelper/install_helper.c"

grep -q "Embed SMCHelper Artifacts" "$PROJECT_FILE" \
    || fail "app target does not embed SMCHelper artifacts"

# The helper is built by the SMCControllerHelper Xcode target (prepare_bundle.sh was
# removed with the XPC migration), so check the project instead of a build script.
grep -q "SMCControllerHelper" "$PROJECT_FILE" \
    || fail "project has no SMCControllerHelper target"

grep -q "path = SMCController/Platform/SMCBridge.c" "$PROJECT_FILE" \
    || fail "helper target does not compile SMCBridge.c from Platform"

if grep -q "../SMCController/SMCBridge" "$DAEMON_SOURCE"; then
    fail "helper sources still reference the removed SMCBridge path"
fi

grep -q '#include "SMCBridge.h"' "$DAEMON_SOURCE" \
    || fail "main_daemon.c does not include SMCBridge.h through an include path"

# Since the XPC migration, installation succeeds only once the new helper answers the
# XPC status check, which also catches an installer that stopped part way.
grep -A20 "func installHelperFromBundle" "$DAEMON_CLIENT" | grep -q "helperAvailability().isReady" \
    || fail "DaemonClient does not confirm the helper over XPC after installing it"

grep -q "/bin/launchctl bootstrap system" "$INSTALLER_SOURCE" \
    || fail "install_helper.c does not bootstrap the helper into the system launchd domain"

grep -q "/bin/launchctl kickstart -k system/" "$INSTALLER_SOURCE" \
    || fail "install_helper.c does not kickstart the system LaunchDaemon after bootstrap"

if grep -q 'launchctl load ' "$INSTALLER_SOURCE"; then
    fail "install_helper.c still uses domain-implicit launchctl load"
fi

echo "Helper setup verification passed"
