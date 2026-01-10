#!/bin/bash

echo "=== SMCController Auto-Install Debug ==="
echo ""

# Find the app
APP_PATH=""
if [ -d "/Applications/SMCController.app" ]; then
    APP_PATH="/Applications/SMCController.app"
elif [ -d "$HOME/Library/Developer/Xcode/DerivedData/SMCController"* ]; then
    # Find most recent debug build
    APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "SMCController.app" -type d | grep Debug | head -1)
fi

if [ -z "$APP_PATH" ]; then
    echo "❌ SMCController.app not found"
    echo "   Check: /Applications/ or Xcode DerivedData/"
    exit 1
fi

echo "✅ Found app at: $APP_PATH"
echo ""

# Check bundle structure
echo "=== Bundle Structure ==="
RESOURCES="$APP_PATH/Contents/Resources"
echo "Resources path: $RESOURCES"
echo ""

if [ -d "$RESOURCES/SMCHelper" ]; then
    echo "✅ SMCHelper directory exists"
    echo "Contents:"
    ls -la "$RESOURCES/SMCHelper/"
    echo ""
    
    # Check for install script
    if [ -f "$RESOURCES/SMCHelper/install_daemon.sh" ]; then
        echo "✅ install_daemon.sh found"
        
        # Check if executable
        if [ -x "$RESOURCES/SMCHelper/install_daemon.sh" ]; then
            echo "✅ install_daemon.sh is executable"
        else
            echo "⚠️  install_daemon.sh is NOT executable"
            echo "   Run: chmod +x \"$RESOURCES/SMCHelper/install_daemon.sh\""
        fi
    else
        echo "❌ install_daemon.sh NOT found"
    fi
    
    # Check for other required files
    for file in "main_daemon.c" "com.minepacu.SMCHelper.plist"; do
        if [ -f "$RESOURCES/SMCHelper/$file" ]; then
            echo "✅ $file found"
        else
            echo "❌ $file NOT found"
        fi
    done
else
    echo "❌ SMCHelper directory NOT found"
    echo "   Expected at: $RESOURCES/SMCHelper"
    echo ""
    echo "   To fix:"
    echo "   1. In Xcode: File → Add Files to 'SMCController'"
    echo "   2. Select SMCHelper folder"
    echo "   3. Choose 'Create folder references' (blue folder icon)"
    echo "   4. Check 'Copy items if needed'"
    echo "   5. Check SMCController target"
    echo "   6. Rebuild"
fi

echo ""
echo "=== Current Helper Status ==="

if [ -f "/Library/PrivilegedHelperTools/com.minepacu.SMCHelper" ]; then
    echo "✅ Helper installed"
    ls -la /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
else
    echo "❌ Helper NOT installed"
fi

if pgrep -f "com.minepacu.SMCHelper" > /dev/null; then
    echo "✅ Daemon running"
else
    echo "❌ Daemon NOT running"
fi

if [ -S "/tmp/com.minepacu.SMCHelper.socket" ]; then
    echo "✅ Socket exists"
else
    echo "❌ Socket NOT exists"
fi

echo ""
echo "=== Recommendations ==="
echo ""

if [ ! -d "$RESOURCES/SMCHelper" ]; then
    echo "⚠️  CRITICAL: SMCHelper folder missing from bundle"
    echo "   Auto-install will FAIL"
    echo "   Follow Xcode setup instructions in XCODE_SETUP.md"
elif [ ! -f "$RESOURCES/SMCHelper/install_daemon.sh" ]; then
    echo "⚠️  CRITICAL: install_daemon.sh missing"
    echo "   Auto-install will FAIL"
    echo "   Check if file was excluded from build"
elif [ ! -x "$RESOURCES/SMCHelper/install_daemon.sh" ]; then
    echo "⚠️  install_daemon.sh not executable"
    echo "   Add Run Script Phase in Xcode Build Phases"
else
    echo "✅ Bundle structure looks good"
    echo "   Auto-install should work"
fi
