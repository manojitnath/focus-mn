#!/bin/zsh
# Builds "Focus MN.app" from src/ into build.noindex/ (Spotlight skips folders ending in .noindex,
# so only the installed copy shows up in search). Re-run after editing anything in src/.
#   ./build.sh            build the app
#   ./build.sh --install  also copy it to /Applications and open it
#   ./build.sh --zip      also make build.noindex/Focus-MN.zip for a GitHub release
set -e
here="${0:A:h}"
dir="$here/build.noindex"
out="$dir/Focus MN.app"
version="2.4"

rm -rf "$out"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
swiftc -O -swift-version 5 "$here/src/main.swift" -o "$out/Contents/MacOS/Focus MN"
cp "$here/src/panel.html" "$here/src/dashboard.html" "$here/src/notice.html" "$here/src/AppIcon.icns" "$out/Contents/Resources/"

cat > "$out/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Focus MN</string>
  <key>CFBundleDisplayName</key><string>Focus MN</string>
  <key>CFBundleIdentifier</key><string>local.focusmn.app</string>
  <key>CFBundleExecutable</key><string>Focus MN</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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

if (( ${@[(Ie)--zip]} )); then
  rm -f "$dir/Focus-MN.zip"
  ditto -c -k --keepParent "$out" "$dir/Focus-MN.zip"
  echo "Zipped: $dir/Focus-MN.zip"
fi

if (( ${@[(Ie)--install]} )); then
  osascript -e 'tell application id "local.focusmn.app" to quit' 2>/dev/null || true
  while pgrep -xq "Focus MN"; do sleep 0.2; done
  rm -rf "/Applications/Focus MN.app"
  ditto "$out" "/Applications/Focus MN.app"
  open "/Applications/Focus MN.app"
  echo "Installed: /Applications/Focus MN.app"
fi
