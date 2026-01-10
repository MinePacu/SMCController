#!/bin/bash

# Prepare SMCHelper for app bundle inclusion
# This builds the daemon binary that will be included in the app bundle

cd "$(dirname "$0")"

echo "🔨 Building SMCHelper daemon for bundle..."

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
    rm SMCBridge.o
    exit 1
fi

# Clean up
rm SMCBridge.o

echo "✅ SMCHelper binary built successfully"
ls -la SMCHelper

echo ""
echo "🔨 Building install_helper tool..."

# Build the installer tool
clang install_helper.c -o install_helper

if [ $? -ne 0 ]; then
    echo "❌ Failed to compile install_helper.c"
    exit 1
fi

echo "✅ install_helper built successfully"
ls -la install_helper

echo ""
echo "✅ All binaries ready for bundle inclusion:"
echo "   - SMCHelper (daemon binary)"
echo "   - install_helper (installer tool)"
echo "   - com.minepacu.SMCHelper.plist"
echo ""
echo "Add these files to Xcode project's Copy Bundle Resources"
