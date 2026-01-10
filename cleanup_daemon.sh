#!/bin/bash
# Cleanup script for SMCHelper daemon

echo "🧹 Cleaning up SMCHelper daemon and related processes..."

# Kill all SMCHelper processes
echo "Killing all SMCHelper processes..."
sudo pkill -9 -f "com.minepacu.SMCHelper"

# Unload from launchd
echo "Unloading from launchd..."
sudo launchctl unload /Library/LaunchDaemons/com.minepacu.SMCHelper.plist 2>/dev/null || true

# Remove socket file
echo "Removing socket file..."
sudo rm -f /tmp/com.minepacu.SMCHelper.socket
sudo rm -f /tmp/com.nohyunsoo.SMCHelper.socket  # Old socket

# Remove PID file
echo "Removing PID file..."
sudo rm -f /tmp/com.minepacu.SMCHelper.pid

# Show remaining processes
echo ""
echo "Checking for remaining SMCHelper processes..."
ps aux | grep -i SMCHelper | grep -v grep || echo "✅ No SMCHelper processes running"

# Show socket status
echo ""
echo "Checking socket files..."
ls -l /tmp/*.socket 2>/dev/null || echo "✅ No socket files found"

# Show PID file status
echo ""
echo "Checking PID file..."
ls -l /tmp/com.minepacu.SMCHelper.pid 2>/dev/null || echo "✅ No PID file found"

# Show launchd status
echo ""
echo "Checking launchd status..."
sudo launchctl list | grep -i smc || echo "✅ Not loaded in launchd"

echo ""
echo "✅ Cleanup complete!"
echo "You can now rebuild and test the app."
