#!/bin/bash

# This script is intentionally diagnostic-only: it never installs, bootstraps,
# kickstarts, or otherwise starts the privileged helper.
set -u

HELPER_LABEL="com.minepacu.SMCHelper"
HELPER_PATH="/Library/PrivilegedHelperTools/${HELPER_LABEL}"
PLIST_PATH="/Library/LaunchDaemons/${HELPER_LABEL}.plist"
CLIENT_CONFIG_PATH="/Library/PrivilegedHelperTools/${HELPER_LABEL}.client-requirement.plist"
FAILURES=0
XPC_CHECK=0
APP_BUNDLE=""

usage() {
    echo "Usage: $0 [--xpc-check [path-to-SMCController.app]]" >&2
}

if [ "$#" -gt 0 ]; then
    case "$1" in
        --xpc-check)
            XPC_CHECK=1
            shift
            if [ "$#" -gt 0 ]; then
                APP_BUNDLE="$1"
                shift
            else
                APP_BUNDLE="/Applications/SMCController.app"
            fi
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac

    if [ "$#" -ne 0 ]; then
        usage
        exit 2
    fi
fi

pass() {
    echo "✅ $1"
}

fail() {
    echo "❌ $1"
    FAILURES=$((FAILURES + 1))
}

root_owned_private_file() {
    local path="$1"
    local name="$2"
    local metadata
    local owner
    local mode

    if [ ! -f "$path" ]; then
        fail "$name not found: $path"
        return
    fi

    metadata=$(stat -f '%u %Lp' "$path" 2>/dev/null) || {
        fail "Could not inspect $name: $path"
        return
    }
    owner=${metadata%% *}
    mode=${metadata##* }

    if [ "$owner" != "0" ]; then
        fail "$name is not owned by root: $path"
    elif [ $((8#$mode & 0022)) -ne 0 ]; then
        fail "$name is writable by group or other users (mode $mode): $path"
    else
        pass "$name is root-owned and not group/world writable"
    fi
}

echo "=== Privileged Helper Verification ==="
echo

root_owned_private_file "$HELPER_PATH" "Helper binary"
root_owned_private_file "$PLIST_PATH" "LaunchDaemon plist"

if [ -f "$CLIENT_CONFIG_PATH" ]; then
    config_metadata=$(stat -f '%u %Lp' "$CLIENT_CONFIG_PATH" 2>/dev/null || true)
    config_owner=${config_metadata%% *}
    config_mode=${config_metadata##* }
    if [ "$config_owner" = "0" ] && [ "$config_mode" = "600" ]; then
        pass "Client signing-requirement configuration is root-owned with mode 0600"
    else
        fail "Client signing-requirement configuration must be root-owned with mode 0600"
    fi
else
    fail "Client signing-requirement configuration not found: $CLIENT_CONFIG_PATH"
fi

if [ -f "$HELPER_PATH" ]; then
    if /usr/bin/codesign --verify --strict "$HELPER_PATH" >/dev/null 2>&1; then
        pass "Installed helper passes strict code-signature verification"
    else
        fail "Installed helper does not pass strict code-signature verification"
    fi
fi

if [ -f "$PLIST_PATH" ]; then
    if /usr/bin/plutil -extract "MachServices.${HELPER_LABEL}" raw -o - "$PLIST_PATH" 2>/dev/null | /usr/bin/grep -qx "true"; then
        pass "LaunchDaemon declares Mach service ${HELPER_LABEL}"
    else
        fail "LaunchDaemon does not declare Mach service ${HELPER_LABEL}"
    fi
fi

if /bin/launchctl print "system/${HELPER_LABEL}" >/dev/null 2>&1; then
    pass "LaunchDaemon is registered with launchd"
else
    fail "LaunchDaemon is not registered with launchd (or cannot be inspected by this user)"
fi

echo
if [ "$FAILURES" -ne 0 ]; then
    echo
    echo "Verification failed with ${FAILURES} issue(s)."
    exit 1
fi

if [ "$XPC_CHECK" -eq 1 ]; then
    echo
    echo "=== Authenticated XPC Check ==="

    if [ ! -d "$APP_BUNDLE" ]; then
        fail "SMCController app bundle not found: $APP_BUNDLE"
    elif ! /usr/bin/codesign --verify --strict "$APP_BUNDLE" >/dev/null 2>&1; then
        fail "SMCController app does not pass strict code-signature verification: $APP_BUNDLE"
    else
        executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)
        app_binary="$APP_BUNDLE/Contents/MacOS/$executable_name"
        if [ -z "$executable_name" ] || [ ! -x "$app_binary" ]; then
            fail "SMCController executable not found in app bundle: $APP_BUNDLE"
        else
            xpc_output=$("$app_binary" --xpc-check 2>&1)
            xpc_status=$?
            printf '%s\n' "$xpc_output"

            if [ "$xpc_status" -eq 0 ] && [ "$xpc_output" = "XPC_CHECK: ready" ]; then
                pass "Signed SMCController app completed the authenticated XPC check"
            else
                fail "Signed SMCController app did not complete the authenticated XPC check"
            fi
        fi
    fi
fi

if [ "$FAILURES" -ne 0 ]; then
    echo
    echo "Verification failed with ${FAILURES} issue(s)."
    exit 1
fi

echo
echo "Verification passed."
