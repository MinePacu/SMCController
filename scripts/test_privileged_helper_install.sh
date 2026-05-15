#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/Build/Products/Release/SMCController.app"
HELPER_RESOURCE_DIR="$APP_PATH/Contents/Resources/SMCHelper"
HELPER_DST="/Library/PrivilegedHelperTools/com.minepacu.SMCHelper"
PLIST_DST="/Library/LaunchDaemons/com.minepacu.SMCHelper.plist"
SOCKET_PATH="/tmp/com.minepacu.SMCHelper.socket"

DO_RESET=0
DO_BUILD=0
DO_OPEN=0
DO_VERIFY=0
DO_PROMPT=0
PLAN_ONLY=0
ASSUME_YES=0

usage() {
    cat <<'EOF'
Usage:
  scripts/test_privileged_helper_install.sh [options]

Options:
  --reset        Remove the installed helper, LaunchDaemon plist, and socket.
  --build        Rebuild helper artifacts and the Release app.
  --open-app     Open the built app so you can enable fan control in the UI.
  --verify       Verify installed helper files, launchd state, socket, and euid.
  --full         Run reset, build, open-app, wait for UI install, then verify.
  --yes          Do not ask for confirmation before --reset.
  --plan         Print the selected steps without executing them.
  --help         Show this help.

Typical clean install test:
  scripts/test_privileged_helper_install.sh --full

Non-destructive packaging check:
  scripts/test_privileged_helper_install.sh --build --verify
EOF
}

log() {
    printf '%s\n' "$*"
}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

confirm_reset() {
    if [ "$ASSUME_YES" -eq 1 ]; then
        return
    fi

    log "This will unload/remove:"
    log "  $HELPER_DST"
    log "  $PLIST_DST"
    log "  $SOCKET_PATH"
    printf 'Continue? [y/N] '
    read -r answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) fail "reset cancelled" ;;
    esac
}

print_plan() {
    log "Selected helper install test steps:"
    if [ "$DO_RESET" -eq 1 ]; then
        log "  - Reset existing privileged helper installation"
    fi
    if [ "$DO_BUILD" -eq 1 ]; then
        log "  - Build helper artifacts and app"
    fi
    if [ "$DO_OPEN" -eq 1 ]; then
        log "  - Open app for UI-triggered helper installation"
    fi
    if [ "$DO_PROMPT" -eq 1 ]; then
        log "  - Wait for you to enable fan control in the app"
    fi
    if [ "$DO_VERIFY" -eq 1 ]; then
        log "  - Verify installed helper state"
    fi
}

reset_installation() {
    confirm_reset

    log "Stopping existing helper..."
    sudo launchctl unload "$PLIST_DST" 2>/dev/null || true
    sudo pkill -f "com.minepacu.SMCHelper" 2>/dev/null || true

    log "Removing installed helper files..."
    sudo rm -f "$PLIST_DST"
    sudo rm -f "$HELPER_DST"
    sudo rm -f "$SOCKET_PATH"
    sudo rm -f /tmp/com.minepacu.SMCHelper.pid
}

build_app() {
    log "Building helper artifacts..."
    (cd "$ROOT_DIR" && bash SMCHelper/prepare_bundle.sh)

    log "Building Release app..."
    (cd "$ROOT_DIR" && xcodebuild \
        -project SMCController.xcodeproj \
        -scheme SMCController \
        -configuration Release \
        -derivedDataPath build \
        clean build \
        CODE_SIGNING_ALLOWED=NO)

    verify_bundle_resources
}

verify_bundle_resources() {
    [ -d "$HELPER_RESOURCE_DIR" ] || fail "helper resource directory missing: $HELPER_RESOURCE_DIR"
    [ -x "$HELPER_RESOURCE_DIR/SMCHelper" ] || fail "bundled SMCHelper missing or not executable"
    [ -x "$HELPER_RESOURCE_DIR/install_helper" ] || fail "bundled install_helper missing or not executable"
    [ -f "$HELPER_RESOURCE_DIR/com.minepacu.SMCHelper.plist" ] || fail "bundled LaunchDaemon plist missing"
    log "Bundled helper resources are present."
}

open_app() {
    [ -d "$APP_PATH" ] || fail "app not built at $APP_PATH; run with --build first"
    log "Opening app: $APP_PATH"
    open "$APP_PATH"
}

wait_for_ui_install() {
    log ""
    log "In the app, open Privileges and click Enable Fan Control."
    log "Approve the administrator prompt when it appears."
    printf 'Press Return here after the app finishes the helper install attempt... '
    read -r _
}

verify_installation() {
    log "Verifying installed helper..."

    [ -x "$HELPER_DST" ] || fail "installed helper missing or not executable: $HELPER_DST"
    [ -f "$PLIST_DST" ] || fail "LaunchDaemon plist missing: $PLIST_DST"

    helper_owner="$(stat -f '%Su:%Sg' "$HELPER_DST")"
    plist_owner="$(stat -f '%Su:%Sg' "$PLIST_DST")"
    [ "$helper_owner" = "root:wheel" ] || fail "helper owner is $helper_owner, expected root:wheel"
    [ "$plist_owner" = "root:wheel" ] || fail "plist owner is $plist_owner, expected root:wheel"

    if ! sudo launchctl list | grep -q "com.minepacu.SMCHelper"; then
        fail "launchd does not list com.minepacu.SMCHelper"
    fi

    [ -S "$SOCKET_PATH" ] || fail "daemon socket missing: $SOCKET_PATH"

    response="$(printf 'check' | nc -w 2 -U "$SOCKET_PATH" 2>&1)" || {
        printf '%s\n' "$response"
        fail "daemon did not respond on socket"
    }

    log "Daemon response: $response"
    echo "$response" | grep -q "euid=0" || fail "daemon response does not show euid=0"

    log "Privileged helper install verification passed."
}

if [ "$#" -eq 0 ]; then
    usage
    exit 0
fi

while [ "$#" -gt 0 ]; do
    case "$1" in
        --reset) DO_RESET=1 ;;
        --build) DO_BUILD=1 ;;
        --open-app) DO_OPEN=1 ;;
        --verify) DO_VERIFY=1 ;;
        --full)
            DO_RESET=1
            DO_BUILD=1
            DO_OPEN=1
            DO_PROMPT=1
            DO_VERIFY=1
            ;;
        --yes) ASSUME_YES=1 ;;
        --plan) PLAN_ONLY=1 ;;
        --help)
            usage
            exit 0
            ;;
        *) fail "unknown option: $1" ;;
    esac
    shift
done

if [ "$PLAN_ONLY" -eq 1 ]; then
    print_plan
    exit 0
fi

print_plan

if [ "$DO_RESET" -eq 1 ]; then
    reset_installation
fi
if [ "$DO_BUILD" -eq 1 ]; then
    build_app
fi
if [ "$DO_OPEN" -eq 1 ]; then
    open_app
fi
if [ "$DO_PROMPT" -eq 1 ]; then
    wait_for_ui_install
fi
if [ "$DO_VERIFY" -eq 1 ]; then
    verify_installation
fi
