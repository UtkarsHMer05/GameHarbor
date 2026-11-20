#!/bin/bash
# Build SteamPlayMacApp and package it into an ad-hoc signed app.
set -euo pipefail

cd "$(dirname "$0")"

APP=".build/SteamPlayMac Config.app"
BIN_NAME="SteamPlayMacApp"
BUNDLE_ID="com.steamplaymac.app"
ICON_SRC="AppIcon.icns"

if [ ! -f "$ICON_SRC" ]; then
    swift make_icon.swift
fi

swift build -c release

# Keep temporary builds out of Spotlight and the app launcher.
touch .build/.metadata_never_index
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"
printf '1\n' > "$APP/Contents/Resources/manifest-watcher.version"

cp ".build/release/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/$BIN_NAME"
cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"

# Built by the top-level Makefile (make rebuild).
DYLIB_SRC="../out/SteamPlayMac.dylib"
MS_VERSION=$(sed -n 's/.*STEAMPLAYMAC_VERSION[[:space:]]*"\(.*\)".*/\1/p' ../src/version.h)
if [ -f "$DYLIB_SRC" ]; then
    cp "$DYLIB_SRC" "$APP/Contents/Resources/SteamPlayMac.dylib"
    printf '%s' "$MS_VERSION" > "$APP/Contents/Resources/SteamPlayMac.dylib.version"
else
    echo "warning: $DYLIB_SRC missing -- Install pane will report no payload" >&2
fi

SIG_SRC="../signatures"
if [ -d "$SIG_SRC" ]; then
    cp -R "$SIG_SRC" "$APP/Contents/Resources/signatures"
else
    echo "warning: $SIG_SRC missing -- hooks won't resolve without signatures" >&2
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>SteamPlayMac Config</string>
    <key>CFBundleDisplayName</key>     <string>SteamPlayMac Config</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>$BIN_NAME</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.8.2</string>
    <key>CFBundleVersion</key>         <string>13</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key> <string>© 2026 Selectively11</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
</dict>
</plist>
PLIST

SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
else
    echo "warning: Sparkle.framework not found -- auto-update disabled at runtime" >&2
fi

echo "APPL????" > "$APP/Contents/PkgInfo"

touch "$APP"

codesign -fs - "$APP"

echo "Built $APP"
codesign -dv "$APP" 2>&1 | head -3 || true
