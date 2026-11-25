#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"          # app/
project="${root:h}"        # Agent额度/
build="$root/.build"
app="$root/dist/Agent 额度.app"
contents="$app/Contents"

python3 "$root/Scripts/gen-palette.py"
if [[ ! -f "$root/AppBundle/AppIcon-1024.png" ]]; then
  python3 "$root/Scripts/make-icon.py" >/dev/null 2>&1 || true
fi

rm -rf "$app"
mkdir -p "$build" "$contents/MacOS" "$contents/Resources/web"

swiftc \
  -module-cache-path "$build/modulecache" \
  -swift-version 5 \
  -framework AppKit -framework WebKit -framework Carbon \
  -o "$build/AgentQuotaCard" \
  "$root"/Sources/*.swift

cp "$build/AgentQuotaCard" "$contents/MacOS/AgentQuotaCard"
cp "$root/AppBundle/Info.plist" "$contents/Info.plist"
chmod +x "$contents/MacOS/AgentQuotaCard"

cp "$project/index.html" "$project/styles.css" "$project/app.js" "$project/palette.css" "$project/palette.js" "$contents/Resources/web/"
print -r -- 'window.AGENT_QUOTA = {};' > "$contents/Resources/web/data.js"

icon="$root/AppBundle/AppIcon-1024.png"
if [[ -f "$icon" ]]; then
  iconset="$build/AppIcon.iconset"
  rm -rf "$iconset"
  mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$app" >/dev/null 2>&1 || true
print -r -- "$app"
