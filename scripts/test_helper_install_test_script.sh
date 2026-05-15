#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/test_privileged_helper_install.sh"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[ -x "$SCRIPT" ] || fail "test_privileged_helper_install.sh is missing or not executable"

HELP_OUTPUT="$("$SCRIPT" --help)"
echo "$HELP_OUTPUT" | grep -q -- "--reset" || fail "help does not document --reset"
echo "$HELP_OUTPUT" | grep -q -- "--build" || fail "help does not document --build"
echo "$HELP_OUTPUT" | grep -q -- "--open-app" || fail "help does not document --open-app"
echo "$HELP_OUTPUT" | grep -q -- "--verify" || fail "help does not document --verify"
echo "$HELP_OUTPUT" | grep -q -- "--full" || fail "help does not document --full"

PLAN_OUTPUT="$("$SCRIPT" --plan --build --verify)"
echo "$PLAN_OUTPUT" | grep -q "Build helper artifacts and app" || fail "plan omits build step"
echo "$PLAN_OUTPUT" | grep -q "Verify installed helper state" || fail "plan omits verify step"

echo "Helper install test script checks passed"
