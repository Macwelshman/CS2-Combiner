#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PRODUCT_NAME="CS2TextureCombiner"
APP_NAME="CS2 Combiner"
BUNDLE_ID="com.ianmaclarty.CS2TextureCombiner"
MIN_SYSTEM_VERSION="14.0"
BUILD_CONFIGURATION="${CS2_COMBINER_BUILD_CONFIGURATION:-debug}"
VERSION="0.3.3"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
SCRATCH_DIR="${CS2_COMBINER_SCRATCH_DIR:-${TMPDIR:-/tmp}/CS2CombinerBuild}"
MODULE_CACHE="${CS2_COMBINER_MODULE_CACHE:-${TMPDIR:-/tmp}/CS2CombinerModuleCache}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RELEASE_ZIP="$DIST_DIR/CS2-Combiner-$VERSION-macos.zip"

pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
mkdir -p "$MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"

swift build \
  --disable-sandbox \
  --scratch-path "$SCRATCH_DIR" \
  -c "$BUILD_CONFIGURATION" \
  --product "$PRODUCT_NAME"
BUILD_BINARY="$(swift build \
  --disable-sandbox \
  --scratch-path "$SCRATCH_DIR" \
  -c "$BUILD_CONFIGURATION" \
  --show-bin-path)/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi
if [[ -f "$ROOT_DIR/Resources/Icons/NormalizeGlobe.png" ]]; then
  cp "$ROOT_DIR/Resources/Icons/NormalizeGlobe.png" "$APP_RESOURCES/NormalizeGlobe.png"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Texture images and folders</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.image</string>
        <string>public.folder</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# SwiftPM emits a linker-signed Mach-O. Sign the complete bundle ad-hoc so its
# executable and resources form one internally consistent local app. This is
# not a Developer ID signature and does not imply notarisation.
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"

package_release() {
  rm -f "$RELEASE_ZIP"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$RELEASE_ZIP"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PRODUCT_NAME\""
    ;;
  --verify|verify)
    plutil -lint "$INFO_PLIST"
    open_app
    sleep 1
    pgrep -x "$PRODUCT_NAME" >/dev/null
    ;;
  --package|package)
    package_release
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--verify|--package]" >&2
    exit 2
    ;;
esac
