#!/bin/bash

# SMCController 빌드 및 테스트 스크립트

echo "🔨 Building SMCController (Release mode)..."

cd "$(dirname "$0")"

# Clean build
rm -rf build/

# Build for Release
xcodebuild -project SMCController.xcodeproj \
           -scheme SMCController \
           -configuration Release \
           -derivedDataPath build \
           clean build \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    APP_PATH="build/Build/Products/Release/SMCController.app"
    
    if [ -d "$APP_PATH" ]; then
        echo ""
        echo "📦 App location: $APP_PATH"
        echo ""
        echo "▶️  To run:"
        echo "   open '$APP_PATH'"
        echo ""
        echo "🔍 To see console logs:"
        echo "   Console.app > Show Process 'SMCController'"
        echo ""
        echo "🚀 Opening app now..."
        open "$APP_PATH"
    else
        echo "❌ App not found at expected location"
    fi
else
    echo "❌ Build failed"
    exit 1
fi
