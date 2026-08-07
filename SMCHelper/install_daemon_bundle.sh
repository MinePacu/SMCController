#!/bin/bash
set -euo pipefail

# Retired: this script previously copied a prebuilt helper into the app's
# install path. The app now embeds Xcode-built artifacts and invokes the
# installer with its own signed bundle path.
echo "install_daemon_bundle.sh is retired. Install SMCHelper from SMCController.app."
exit 1
