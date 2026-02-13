#!/bin/bash
set -euo pipefail

# Build BG3 Mac Mod Manager as a distributable .app bundle
# Usage: ./scripts/build-app.sh [--sign "Developer ID Application: Name (TeamID)"]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="BG3 Mac Mod Manager"
BUNDLE_NAME="BG3MacModManager"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"

SIGN_IDENTITY=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--sign \"Developer ID Application: Name (TeamID)\"]"
            exit 1
            ;;
    esac
done

echo "=== Building ${APP_NAME} ==="

# Clean previous build
rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR"

# Build release binary (universal binary for Intel + Apple Silicon)
echo "Building release binary (universal)..."
cd "$PROJECT_DIR"
swift build -c release --arch arm64 --arch x86_64

# Find the built binary
BINARY=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${BUNDLE_NAME}

if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY"
    exit 1
fi

echo "Binary built at: $BINARY"

# Create .app bundle structure
echo "Assembling .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/${BUNDLE_NAME}"

# Copy Info.plist
cp "$PROJECT_DIR/Sources/${BUNDLE_NAME}/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy app icon if it exists
if [ -d "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
elif [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "Note: No AppIcon.icns found — app will use a generic icon."
    echo "      Place an AppIcon.icns in the project root or Resources/ folder."
fi

# Code sign
if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: $SIGN_IDENTITY"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    echo "Verifying signature..."
    codesign --verify --verbose "$APP_BUNDLE"
else
    echo "Ad-hoc signing (for local use)..."
    codesign --force --sign - "$APP_BUNDLE"
fi

# Show result
APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo ""
echo "=== Build Complete ==="
echo "App:  $APP_BUNDLE"
echo "Size: $APP_SIZE"
echo ""

if [ -z "$SIGN_IDENTITY" ]; then
    echo "To distribute publicly, re-run with signing:"
    echo "  $0 --sign \"Developer ID Application: Your Name (TEAMID)\""
    echo ""
    echo "Then notarize with:"
    echo "  ditto -c -k --keepParent \"$APP_BUNDLE\" \"$BUILD_DIR/${APP_NAME}.zip\""
    echo "  xcrun notarytool submit \"$BUILD_DIR/${APP_NAME}.zip\" --apple-id YOU@EMAIL --team-id TEAMID --wait"
    echo "  xcrun stapler staple \"$APP_BUNDLE\""
fi

# Create DMG for distribution
DMG_PATH="$BUILD_DIR/${APP_NAME}.dmg"
echo "Creating DMG..."
hdiutil create -volname "${APP_NAME}" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"
echo "DMG created: $DMG_PATH"
