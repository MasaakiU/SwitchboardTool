#!/bin/zsh
# Build both apps and assemble them as .app bundles in build/.
# Signing is ad-hoc: after every rebuild the Accessibility permission has to be granted again.
set -euo pipefail
cd "$(dirname "$0")"
IDENTITY="${CODESIGN_IDENTITY:--}"
swift build -c release --scratch-path .build --cache-path .cache
mkdir -p build

make_bundle() {   # executable name, bundle id, display name
  local name=$1 bundle_id=$2 display=$3
  local app=build/$name.app
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  cp ".build/release/$name" "$app/Contents/MacOS/$name"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleName</key><string>$display</string>
  <key>CFBundleDisplayName</key><string>$display</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
  codesign --force --sign "$IDENTITY" "$app"
  echo "built $(pwd)/$app"
}

make_bundle TouchProbe      io.github.masaakiu.switchboardtool.touchprobe "TouchProbe"
make_bundle SwitchboardTool io.github.masaakiu.switchboardtool            "Switchboard Tool"

# An ad-hoc signature's code hash (cdhash) changes with every build. If an old permission record is left behind,
# macOS treats the app as "does not match the record" and the permission stays ineffective even when switched on.
# Delete the records so the next launch creates fresh ones.
for id in io.github.masaakiu.switchboardtool io.github.masaakiu.switchboardtool.touchprobe; do
  tccutil reset Accessibility "$id" >/dev/null 2>&1 || true
done
echo "Accessibility permission records were reset. The next launch will ask again; switch the app on in System Settings."
