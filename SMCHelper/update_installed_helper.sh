#!/bin/bash
set -euo pipefail

# Retired: source-tree updates bypass the app-signature validation required by
# the XPC listener. Reinstall through the packaged app instead.
echo "update_installed_helper.sh is retired. Reinstall from SMCController.app."
exit 1
