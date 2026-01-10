#!/bin/bash

# Build SMCHelper binary

cd "$(dirname "$0")"

echo "🔨 Building SMCHelper..."

# Compile SMCBridge.c
clang -c ../SMCController/SMCBridge.c -o SMCBridge.o \
    -framework IOKit -framework CoreFoundation

if [ $? -ne 0 ]; then
    echo "❌ Failed to compile SMCBridge.c"
    exit 1
fi

# Compile main.c and link
clang main.c SMCBridge.o -o SMCHelper \
    -framework IOKit -framework CoreFoundation

if [ $? -ne 0 ]; then
    echo "❌ Failed to compile main.c"
    exit 1
fi

# Clean up
rm SMCBridge.o

echo "✅ SMCHelper built successfully"
echo "📦 Binary: $(pwd)/SMCHelper"
echo ""
echo "🧪 Testing helper (requires sudo)..."
echo ""

sudo ./SMCHelper check

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Helper is working!"
    echo ""
    echo "📋 Installing to /Library/PrivilegedHelperTools/..."
    sudo mkdir -p /Library/PrivilegedHelperTools
    sudo cp SMCHelper /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
    sudo chmod 755 /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
    sudo chown root:wheel /Library/PrivilegedHelperTools/com.minepacu.SMCHelper
    
    echo "✅ Helper installed to /Library/PrivilegedHelperTools/com.minepacu.SMCHelper"
else
    echo ""
    echo "❌ Helper test failed"
    exit 1
fi
