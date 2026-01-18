#!/bin/bash
set -euo pipefail

# Update the installed SMCHelper daemon from the current source tree.
# Requires sudo.

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_BIN="$ROOT_DIR/SMCHelper"
PLIST_SRC="$ROOT_DIR/com.minepacu.SMCHelper.plist"
HELPER_DST="/Library/PrivilegedHelperTools/com.minepacu.SMCHelper"
PLIST_DST="/Library/LaunchDaemons/com.minepacu.SMCHelper.plist"

echo "🔨 Building SMCHelper..."
cd "$ROOT_DIR"
./prepare_bundle.sh

echo "🛑 Unloading existing daemon (if any)..."
sudo launchctl unload "$PLIST_DST" 2>/dev/null || true
sudo pkill -f "$HELPER_DST" 2>/dev/null || true
sudo rm -f /tmp/com.minepacu.SMCHelper.socket

echo "📥 Installing binaries..."
sudo cp "$HELPER_BIN" "$HELPER_DST"
sudo cp "$PLIST_SRC" "$PLIST_DST"
sudo chown root:wheel "$HELPER_DST" "$PLIST_DST"
sudo chmod 755 "$HELPER_DST"
sudo chmod 644 "$PLIST_DST"

echo "🚀 Loading daemon..."
sudo launchctl load "$PLIST_DST"

echo "✅ Done."
echo "Check status:"
echo "  sudo launchctl list | grep SMCHelper"
echo "  ls -la /tmp/com.minepacu.SMCHelper.socket"
