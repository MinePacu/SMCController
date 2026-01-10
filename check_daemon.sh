#!/bin/bash

echo "=== Daemon Status Check ==="
echo ""

# Check if daemon binary exists
if [ -f "/Library/PrivilegedHelperTools/com.minepacu.SMCHelper" ]; then
    echo "✅ Daemon binary installed at /Library/PrivilegedHelperTools/com.minepacu.SMCHelper"
    ls -la /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
else
    echo "❌ Daemon binary NOT found"
    echo "   Run: cd SMCHelper && sudo ./install_daemon.sh"
fi

echo ""

# Check if daemon is running
if pgrep -f "com.minepacu.SMCHelper" > /dev/null; then
    echo "✅ Daemon process is running:"
    ps aux | grep SMCHelper | grep -v grep
else
    echo "❌ Daemon process NOT running"
fi

echo ""

# Check if socket exists
if [ -S "/tmp/com.minepacu.SMCHelper.socket" ]; then
    echo "✅ Daemon socket exists:"
    ls -la /tmp/com.minepacu.SMCHelper.socket
    
    # Try to communicate with daemon
    echo ""
    echo "Testing daemon communication..."
    response=$(echo "check" | nc -w 2 -U /tmp/com.minepacu.SMCHelper.socket 2>&1)
    if [ $? -eq 0 ]; then
        echo "✅ Daemon responded: $response"
        if echo "$response" | grep -q "euid=0"; then
            echo "✅ Daemon is running with root privileges"
        else
            echo "⚠️  Daemon is NOT running as root!"
        fi
    else
        echo "❌ Could not communicate with daemon"
    fi
else
    echo "❌ Daemon socket NOT found"
fi

echo ""
echo "=== App Running Status ==="

# Check if app is running as root
if ps aux | grep "SMCController.app" | grep -v grep | grep "^root" > /dev/null; then
    echo "⚠️  WARNING: App is running as ROOT (not recommended)"
    echo "   The app should run as regular user and use daemon for privileges"
else
    current_user=$(ps aux | grep "SMCController.app" | grep -v grep | awk '{print $1}' | head -1)
    if [ -n "$current_user" ]; then
        echo "✅ App is running as user: $current_user (correct)"
    else
        echo "ℹ️  App is not currently running"
    fi
fi
