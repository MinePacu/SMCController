#!/bin/bash

echo "=== SMCController Auto-Install Debug ==="
echo ""

# Find the app
APP_PATH=""
if [ -d "/Applications/SMCController.app" ]; then
    APP_PATH="/Applications/SMCController.app"
else
    # Fall back to the most recent Debug build in Xcode's DerivedData.
    # SC2144: `[ -d glob* ]` does not expand globs, so we just run the find
    # directly and rely on the empty-result check below.
    APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "SMCController.app" -type d 2>/dev/null | grep Debug | head -1)
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
    
    HELPER="$RESOURCES/SMCHelper/SMCControllerHelper"
    INSTALLER="$RESOURCES/SMCHelper/install_helper"
    PLIST="$RESOURCES/SMCHelper/com.minepacu.SMCHelper.plist"

    for file in "$HELPER" "$INSTALLER" "$PLIST"; do
        if [ -f "$file" ]; then
            echo "✅ $(basename "$file") found"
        else
            echo "❌ $(basename "$file") NOT found"
        fi
    done

    if [ -x "$HELPER" ]; then
        if codesign --verify --strict "$HELPER" 2>/dev/null; then
            echo "✅ Embedded helper signature is valid"
        else
            echo "⚠️  Embedded helper signature could not be verified"
        fi
    fi

    if [ -f "$PLIST" ]; then
        echo "Mach service advertised by LaunchDaemon plist:"
        /usr/libexec/PlistBuddy -c 'Print :MachServices' "$PLIST" 2>/dev/null \
            || echo "⚠️  Could not read MachServices from plist"
    fi
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

if /bin/launchctl print system/com.minepacu.SMCHelper >/dev/null 2>&1; then
    echo "✅ Mach service registered with launchd"
else
    echo "⚠️  Mach service is not registered with launchd"
fi

echo ""
echo "=== Recommendations ==="
echo ""

if [ ! -d "$RESOURCES/SMCHelper" ]; then
    echo "⚠️  CRITICAL: SMCHelper folder missing from bundle"
    echo "   Auto-install will FAIL"
    echo "   Follow Xcode setup instructions in XCODE_SETUP.md"
elif [ ! -x "$RESOURCES/SMCHelper/SMCControllerHelper" ]; then
    echo "⚠️  CRITICAL: signed helper executable missing"
    echo "   Rebuild the SMCControllerHelper target"
elif [ ! -x "$RESOURCES/SMCHelper/install_helper" ]; then
    echo "⚠️  CRITICAL: install_helper missing or not executable"
    echo "   Rebuild the installer target"
elif [ ! -f "$RESOURCES/SMCHelper/com.minepacu.SMCHelper.plist" ]; then
    echo "⚠️  CRITICAL: LaunchDaemon plist missing"
    echo "   Rebuild the app bundle"
else
    echo "✅ Bundle structure looks good"
    echo "   The current signed app can authenticate to the helper over its Mach service"
fi
