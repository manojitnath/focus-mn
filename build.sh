#!/bin/zsh
# Builds build/Focus MN.app from src/. Re-run after editing widget.html or main.swift.
#   ./build.sh          build the app
#   ./build.sh --zip    also make build/Focus-MN.zip for a GitHub release
set -e
here="${0:A:h}"
out="$here/build/Focus MN.app"
version="1.0"

rm -rf "$out"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
swiftc -O -swift-version 5 "$here/src/main.swift" -o "$out/Contents/MacOS/Focus MN"
cp "$here/src/widget.html" "$out/Contents/Resources/"

cat > "$out/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Focus MN</string>
  <key>CFBundleDisplayName</key><string>Focus MN</string>
  <key>CFBundleIdentifier</key><string>local.focusmn.app</string>
  <key>CFBundleExecutable</key><string>Focus MN</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally, not notarized.
codesign --force --deep -s - "$out"
echo "Built: $out"

if [[ "$1" == "--zip" ]]; then
  rm -f "$here/build/Focus-MN.zip"
  ditto -c -k --keepParent "$out" "$here/build/Focus-MN.zip"
  echo "Zipped: $here/build/Focus-MN.zip"
fi
