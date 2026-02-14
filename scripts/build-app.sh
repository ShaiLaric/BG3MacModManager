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
USE_HDIUTIL=false

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
        --use-hdiutil)
            USE_HDIUTIL=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--sign IDENTITY] [--notarize --keychain-profile PROFILE] [--use-hdiutil]"
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

# Remove extended attributes and locked flags before DMG creation
# These can prevent hdiutil from accessing the app bundle
echo "Removing extended attributes from app bundle..."
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
# Remove any immutable flags (uchg) that cause "Operation not permitted"
chflags -R nouchg "$APP_BUNDLE" 2>/dev/null || true

# Show build result
APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo ""
echo "=== Build Complete ==="
echo "App:  $APP_BUNDLE"
echo "Size: $APP_SIZE"
echo ""

# --- Create DMG with /Applications shortcut ---
echo "Creating DMG with Applications shortcut..."

# Clean up any leftover mounted volumes from previous runs
VOLUME_PATH="/Volumes/${APP_NAME}"
if [ -d "$VOLUME_PATH" ]; then
    echo "Unmounting leftover volume: $VOLUME_PATH"
    hdiutil detach "$VOLUME_PATH" -force 2>/dev/null || true
    # Give macOS a moment to fully release the volume
    sleep 1
fi

if command -v create-dmg &> /dev/null && ! $USE_HDIUTIL; then
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
    # Retry once on permission errors (exit code 1) with a delay
    MAX_RETRIES=2
    RETRY_COUNT=0
    SUCCESS=false

    while [ $RETRY_COUNT -lt $MAX_RETRIES ] && ! $SUCCESS; do
        if [ $RETRY_COUNT -gt 0 ]; then
            echo "Retrying create-dmg (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
            sleep 2
        fi

        if create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_PATH" "$APP_BUNDLE"; then
            SUCCESS=true
        else
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 2 ]; then
                # Exit code 2 is non-fatal (background image warning)
                SUCCESS=true
            elif [ $RETRY_COUNT -ge $((MAX_RETRIES - 1)) ]; then
                # Final attempt failed - show diagnostics
                echo "Error: create-dmg failed with exit code $EXIT_CODE"
                echo "Diagnostic information:"
                echo "  - Volume path: $VOLUME_PATH"
                if [ -d "$VOLUME_PATH" ]; then
                    echo "  - Volume is currently mounted"
                    ls -la "$VOLUME_PATH" 2>/dev/null || echo "  - Cannot list volume contents"
                else
                    echo "  - Volume is not mounted"
                fi
                echo "To bypass create-dmg, retry with: $0 --use-hdiutil"
                exit $EXIT_CODE
            fi
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
    done
else
    # Fallback: create DMG with /Applications symlink using hdiutil
    echo "Note: 'create-dmg' not found. Creating basic DMG with /Applications shortcut."
    echo "      For a styled DMG, install: brew install create-dmg"
    echo ""

    # Calculate required size for DMG (app bundle + overhead)
    # Add 50MB for filesystem overhead and Applications symlink
    APP_SIZE_MB=$(du -sm "$APP_BUNDLE" | cut -f1)
    DMG_SIZE=$((APP_SIZE_MB + 50))

    echo "Creating disk image (${DMG_SIZE}MB)..."

    # Step 1: Create empty read-write DMG with HFS+ filesystem
    # HFS+ is the standard for distribution DMGs; APFS has known permission
    # enforcement bugs on mounted volumes (rdar://32629312)
    TEMP_DMG="$BUILD_DIR/temp-${APP_NAME}.dmg"
    rm -f "$TEMP_DMG"
    hdiutil create -size ${DMG_SIZE}m -fs HFS+ -volname "${APP_NAME}" \
        -format UDRW "$TEMP_DMG" >/dev/null || {
        echo "Error: Failed to create empty DMG"
        exit 1
    }

    # Step 2: Mount the DMG with ownership disabled
    # -owners off: prevents permission enforcement on the mounted volume
    # -nobrowse: prevents Finder/Spotlight interference during copy
    echo "Mounting disk image..."
    MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen -owners off -nobrowse "$TEMP_DMG" 2>&1) || {
        echo "Error: Failed to mount DMG"
        echo "$MOUNT_OUTPUT"
        rm -f "$TEMP_DMG"
        exit 1
    }
    VOLUME_PATH=$(echo "$MOUNT_OUTPUT" | grep -o '/Volumes/.*' | head -1)

    if [ -z "$VOLUME_PATH" ]; then
        echo "Error: Could not determine mount path"
        rm -f "$TEMP_DMG"
        exit 1
    fi

    echo "Mounted at: $VOLUME_PATH"

    # Brief pause to allow filesystem to settle after mount
    sleep 1

    # Step 3: Copy files to mounted volume
    # Use ditto (Apple's preferred tool for copying app bundles)
    # It correctly handles code signatures, resource forks, and permissions
    echo "Copying files to disk image..."
    if ditto "$APP_BUNDLE" "$VOLUME_PATH/${APP_NAME}.app"; then
        echo "  Copied with ditto"
    elif rsync -a "$APP_BUNDLE/" "$VOLUME_PATH/${APP_NAME}.app/"; then
        echo "  Copied with rsync (ditto failed)"
    elif cp -R "$APP_BUNDLE" "$VOLUME_PATH/"; then
        echo "  Copied with cp -R (ditto and rsync failed)"
    else
        EXIT_CODE=$?
        echo "Error: Failed to copy app bundle to DMG (all methods failed)"
        echo "Diagnostic information:"
        echo "  Volume mount info:"
        mount | grep "$VOLUME_PATH" || echo "  (volume not in mount table)"
        echo "  Volume permissions:"
        ls -la "$VOLUME_PATH/" 2>/dev/null || echo "  (cannot list volume)"
        echo "  App bundle permissions:"
        ls -la "$APP_BUNDLE" 2>/dev/null || echo "  (cannot list app bundle)"
        hdiutil detach "$VOLUME_PATH" 2>/dev/null || true
        rm -f "$TEMP_DMG"
        exit $EXIT_CODE
    fi

    ln -s /Applications "$VOLUME_PATH/Applications" || {
        EXIT_CODE=$?
        echo "Error: Failed to create Applications symlink"
        hdiutil detach "$VOLUME_PATH" 2>/dev/null || true
        rm -f "$TEMP_DMG"
        exit $EXIT_CODE
    }

    # Step 4: Unmount the DMG
    echo "Unmounting disk image..."
    sync  # Flush writes before unmount
    sleep 1
    hdiutil detach "$VOLUME_PATH" >/dev/null 2>&1 || {
        echo "Warning: Failed to unmount cleanly, retrying..."
        sleep 3
        hdiutil detach "$VOLUME_PATH" -force >/dev/null 2>&1 || {
            echo "Error: Failed to unmount DMG"
            rm -f "$TEMP_DMG"
            exit 1
        }
    }

    # Step 5: Convert to compressed format
    echo "Compressing disk image..."
    rm -f "$DMG_PATH"
    hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG_PATH" >/dev/null || {
        echo "Error: Failed to compress DMG"
        rm -f "$TEMP_DMG"
        exit 1
    }

    # Cleanup
    rm -f "$TEMP_DMG"

    echo "DMG created successfully: $DMG_PATH"
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
