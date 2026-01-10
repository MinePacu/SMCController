#!/bin/bash

# Build and install SMCHelper daemon
# Can be run with sudo or via AuthorizationExecuteWithPrivileges

cd "$(dirname "$0")"

# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    echo "ℹ️  Running as root (euid=0)"
    SUDO=""
else
    echo "ℹ️  Running as user, will use sudo"
    SUDO="sudo"
fi

echo "🔨 Building SMCHelper daemon..."

# Compile SMCBridge.c
clang -c ../SMCController/SMCBridge.c -o SMCBridge.o \
    -framework IOKit -framework CoreFoundation

if [ $? -ne 0 ]; then
    echo "❌ Failed to compile SMCBridge.c"
    exit 1
fi

# Compile main_daemon.c and link
clang main_daemon.c SMCBridge.o -o SMCHelper \
    -framework IOKit -framework CoreFoundation

if [ $? -ne 0 ]; then
    echo "❌ Failed to compile main_daemon.c"
    exit 1
fi

# Clean up
rm SMCBridge.o

echo "✅ SMCHelper daemon built successfully"
echo ""

# Install
echo "📦 Installing helper daemon..."

$SUDO mkdir -p /Library/PrivilegedHelperTools
$SUDO cp SMCHelper /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
$SUDO chmod 755 /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
$SUDO chown root:wheel /Library/PrivilegedHelperTools/com.minepacu.SMCHelper

echo "✅ Helper installed to /Library/PrivilegedHelperTools/com.minepacu.SMCHelper"
echo ""

# Install LaunchDaemon
echo "📦 Installing LaunchDaemon..."

$SUDO cp com.minepacu.SMCHelper.plist /Library/LaunchDaemons/
$SUDO chmod 644 /Library/LaunchDaemons/com.minepacu.SMCHelper.plist
$SUDO chown root:wheel /Library/LaunchDaemons/com.minepacu.SMCHelper.plist

echo "✅ LaunchDaemon plist installed"
echo ""

# Unload old daemon if running
echo "🔄 Restarting daemon..."
$SUDO launchctl unload /Library/LaunchDaemons/com.minepacu.SMCHelper.plist 2>/dev/null

# Load daemon
$SUDO launchctl load /Library/LaunchDaemons/com.minepacu.SMCHelper.plist

if [ $? -eq 0 ]; then
    echo "✅ Daemon started successfully"
    echo ""
    
    # Test daemon
    sleep 1
    echo "🧪 Testing daemon..."
    
    # Send test command to socket
    echo "check" | nc -U /tmp/com.minepacu.SMCHelper.socket
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ Installation complete! Helper daemon is running."
    else
        echo ""
        echo "⚠️ Daemon may not be responding yet. Check with:"
        echo "   sudo launchctl list | grep SMCHelper"
        echo "   sudo tail -f /var/log/system.log | grep SMCHelper"
    fi
else
    echo "❌ Failed to start daemon"
    exit 1
fi
