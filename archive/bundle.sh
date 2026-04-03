#!/bin/bash
# Builds MrMouse and packages it into a proper .app bundle
set -e

APP_NAME="MrMouse"
BUILD_DIR=".build/debug"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$BUNDLE_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building..."
swift build

echo "Creating app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"

# Copy Info.plist
cp "Sources/MrMouse/Info.plist" "$CONTENTS/Info.plist"

# Copy resources (icon etc) from SPM bundle
if [ -d "$BUILD_DIR/MrMouse_MrMouse.bundle" ]; then
    cp -R "$BUILD_DIR/MrMouse_MrMouse.bundle" "$RESOURCES/MrMouse_MrMouse.bundle"
fi

# Add required keys for permission prompts
/usr/libexec/PlistBuddy -c "Delete :CFBundleExecutable" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$CONTENTS/Info.plist"

/usr/libexec/PlistBuddy -c "Delete :NSInputMonitoringUsageDescription" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSInputMonitoringUsageDescription string 'MrMouse needs Input Monitoring access to communicate with your Logitech mouse via HID++.'" "$CONTENTS/Info.plist"

/usr/libexec/PlistBuddy -c "Delete :NSAccessibilityUsageDescription" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSAccessibilityUsageDescription string 'MrMouse needs Accessibility access to remap mouse buttons and perform gesture actions.'" "$CONTENTS/Info.plist"

/usr/libexec/PlistBuddy -c "Delete :CFBundlePackageType" "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS/Info.plist"

echo "Done: $BUNDLE_DIR"
echo ""
echo "Run with:  open $BUNDLE_DIR"
echo ""
echo "To grant permissions:"
echo "  System Settings > Privacy & Security > Input Monitoring → enable MrMouse"
echo "  System Settings > Privacy & Security > Accessibility → enable MrMouse"
