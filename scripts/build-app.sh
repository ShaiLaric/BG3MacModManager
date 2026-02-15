#!/bin/bash
set -euo pipefail

# Build BG3 Mac Mod Manager as a distributable .app bundle with styled DMG
#
# Usage:
#   ./scripts/build-app.sh                                        # Ad-hoc signing (local use)
#   ./scripts/build-app.sh --sign "Developer ID Application: Name (TeamID)"
#   ./scripts/build-app.sh --sign "Developer ID Application: Name (TeamID)" \
#       --notarize --keychain-profile "BG3MacModManager"
#
# First-time notarization setup (store credentials once):
#   xcrun notarytool store-credentials "BG3MacModManager" \
#       --apple-id you@email.com --team-id TEAMID --password <app-specific-password>
#
# For a styled DMG with icon positioning, install create-dmg:
#   brew install create-dmg

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="BG3 Mac Mod Manager"
BUNDLE_NAME="BG3MacModManager"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
DMG_PATH="$BUILD_DIR/${APP_NAME}.dmg"

SIGN_IDENTITY=""
NOTARIZE=false
KEYCHAIN_PROFILE=""
APPLE_ID=""
TEAM_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        --keychain-profile)
            KEYCHAIN_PROFILE="$2"
            shift 2
            ;;
        --apple-id)
            APPLE_ID="$2"
            shift 2
            ;;
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--sign IDENTITY] [--notarize --keychain-profile PROFILE]"
            exit 1
            ;;
    esac
done

# Validate notarization options
if $NOTARIZE; then
    if [ -z "$SIGN_IDENTITY" ]; then
        echo "Error: --notarize requires --sign with a Developer ID"
        exit 1
    fi
    if [ -z "$KEYCHAIN_PROFILE" ] && { [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ]; }; then
        echo "Error: --notarize requires either --keychain-profile or both --apple-id and --team-id"
        exit 1
    fi
fi

echo "=== Building ${APP_NAME} ==="

# Clean previous build
rm -rf "$APP_BUNDLE" "$DMG_PATH"
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
ICON_PATH=""
if [ -d "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    ICON_PATH="$PROJECT_DIR/Resources/AppIcon.icns"
elif [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    ICON_PATH="$PROJECT_DIR/AppIcon.icns"
else
    echo "Note: No AppIcon.icns found — app will use a generic icon."
    echo "      Place an AppIcon.icns in the project root or Resources/ folder."
fi

# Code sign the app bundle
if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing app with: $SIGN_IDENTITY"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    echo "Verifying signature..."
    codesign --verify --verbose "$APP_BUNDLE"
else
    echo "Ad-hoc signing (for local use)..."
    codesign --force --sign - "$APP_BUNDLE"
fi

# Show build result
APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo ""
echo "=== Build Complete ==="
echo "App:  $APP_BUNDLE"
echo "Size: $APP_SIZE"
echo ""

# --- Create DMG with /Applications shortcut ---
echo "Creating DMG with Applications shortcut..."

if command -v create-dmg &> /dev/null; then
    # Use create-dmg for a styled DMG with drag-and-drop layout
    echo "Using create-dmg for styled DMG..."

    CREATE_DMG_ARGS=(
        --volname "${APP_NAME}"
        --window-pos 200 120
        --window-size 660 400
        --icon-size 160
        --icon "${APP_NAME}.app" 180 170
        --app-drop-link 480 170
        --hide-extension "${APP_NAME}.app"
        --no-internet-enable
    )

    # Use app icon as volume icon if available
    if [ -n "$ICON_PATH" ]; then
        CREATE_DMG_ARGS+=(--volicon "$ICON_PATH")
    fi

    # create-dmg returns exit code 2 if it can't set a background image (non-fatal)
    create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_PATH" "$APP_BUNDLE" || {
        EXIT_CODE=$?
        if [ $EXIT_CODE -ne 2 ]; then
            echo "Error: create-dmg failed with exit code $EXIT_CODE"
            exit $EXIT_CODE
        fi
    }
else
    # Fallback: create DMG with /Applications symlink using hdiutil
    echo "Note: 'create-dmg' not found. Creating basic DMG with /Applications shortcut."
    echo "      For a styled DMG, install: brew install create-dmg"
    echo ""

    STAGING_DIR="$BUILD_DIR/dmg-staging"
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"

    cp -R "$APP_BUNDLE" "$STAGING_DIR/"
    ln -s /Applications "$STAGING_DIR/Applications"

    hdiutil create -volname "${APP_NAME}" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

    rm -rf "$STAGING_DIR"
fi

# Sign the DMG itself if using Developer ID
if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing DMG..."
    codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)
echo "DMG created: $DMG_PATH ($DMG_SIZE)"

# --- Notarization ---
if $NOTARIZE; then
    echo ""
    echo "=== Notarizing ==="
    echo "Submitting DMG to Apple for notarization (this may take a few minutes)..."

    NOTARY_ARGS=(submit "$DMG_PATH" --wait)

    if [ -n "$KEYCHAIN_PROFILE" ]; then
        NOTARY_ARGS+=(--keychain-profile "$KEYCHAIN_PROFILE")
    else
        NOTARY_ARGS+=(--apple-id "$APPLE_ID" --team-id "$TEAM_ID")
    fi

    xcrun notarytool "${NOTARY_ARGS[@]}"

    echo "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"

    echo ""
    echo "=== Notarization Complete ==="
    echo "DMG is signed, notarized, and ready for distribution: $DMG_PATH"
elif [ -n "$SIGN_IDENTITY" ]; then
    echo ""
    echo "DMG is signed but NOT notarized."
    echo "macOS Gatekeeper requires notarization for downloaded apps."
    echo ""
    echo "To notarize, first store credentials (one-time setup):"
    echo "  xcrun notarytool store-credentials \"BG3MacModManager\" \\"
    echo "      --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID"
    echo ""
    echo "Then build with notarization:"
    echo "  $0 --sign \"$SIGN_IDENTITY\" --notarize --keychain-profile \"BG3MacModManager\""
else
    echo ""
    echo "To distribute via GitHub Releases, re-run with signing and notarization:"
    echo "  $0 --sign \"Developer ID Application: Your Name (TEAMID)\""
fi
