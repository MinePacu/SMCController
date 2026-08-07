#!/bin/bash
set -euo pipefail

# Retired: this script previously compiled and installed an unauthenticated
# socket daemon. The only supported path is the Xcode-built helper embedded in
# SMCController.app and its bundled install_helper executable.
echo "install_daemon.sh is retired. Install SMCHelper from SMCController.app."
exit 1
