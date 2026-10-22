#!/bin/zsh
# Renders the chosen design from icon.html and writes src/AppIcon.icns. Needs Google Chrome.
#   docs/icon/make-icns.sh        uses design 2 (Timer wedge)
#   docs/icon/make-icns.sh 3      uses another design
set -e
here="${0:A:h}"; root="$here/../.."
design="${1:-2}"
tmp=$(mktemp -d); set=$tmp/AppIcon.iconset; mkdir "$set"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars \
  --default-background-color=00000000 --window-size=1024,1024 --virtual-time-budget=3000 \
  --screenshot="$tmp/icon.png" "file://$here/icon.html?v=$design&size=1024" 2>/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s "$tmp/icon.png" --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$tmp/icon.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
cp "$tmp/icon.png" "$here/icon-$design.png"
iconutil -c icns "$set" -o "$root/src/AppIcon.icns"
rm -rf "$tmp"
echo "Wrote src/AppIcon.icns from design $design"
