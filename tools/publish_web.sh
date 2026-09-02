#!/usr/bin/env bash
# Export the web build into docs/ and make it properly installable on a phone.
# Usage: tools/publish_web.sh      (set GODOT if it is not on PATH)
#
# Godot's PWA export ships 144/180/512 icons, but Chrome on Android wants a 192 before it
# will offer "Install app" rather than a plain shortcut. It also omits short_name. This
# script fixes both after every export, so the fix does not quietly regress next time.
set -eu
BIN="${GODOT:-}"
if [ -z "$BIN" ]; then
  for c in godot godot4 Godot; do command -v "$c" >/dev/null 2>&1 && BIN="$c" && break; done
fi
if [ -z "$BIN" ]; then
  echo "Godot not found. Set GODOT=/path/to/godot (the STANDARD build -- the .NET one" >&2
  echo "cannot export to Web at all)." >&2; exit 1
fi
cd "$(dirname "$0")/.."

# stamped into the build and shown on the menu, so you can tell from the device itself
# whether a push has landed -- an installed web app swaps versions silently
date -u +"%Y-%m-%d %H:%M UTC" > build.txt
echo "build.txt: $(cat build.txt)"

mkdir -p docs
"$BIN" --headless --path . --export-release "Web" docs/index.html

# these two keep the build from fighting the project it came out of
touch docs/.nojekyll   # stop GitHub Pages running Jekyll over it
touch docs/.gdignore   # stop Godot importing the exported PNGs back in as assets
rm -f docs/*.import

cp tools/pwa/icon_192x192.png docs/index.192x192.png
python - <<'PY'
import io, json
p = 'docs/index.manifest.json'
m = json.load(io.open(p, encoding='utf-8'))
m.setdefault('short_name', m.get('name', 'Game'))
if not any(i.get('sizes') == '192x192' for i in m.get('icons', [])):
    m['icons'].append({'sizes': '192x192', 'src': 'index.192x192.png', 'type': 'image/png'})
m['icons'].sort(key=lambda i: int(i['sizes'].split('x')[0]))
json.dump(m, io.open(p, 'w', encoding='utf-8', newline=''), separators=(',', ':'))
print('manifest: display=%s orientation=%s icons=%s'
      % (m['display'], m['orientation'], [i['sizes'] for i in m['icons']]))
PY
echo "Built into docs/. Commit and push; GitHub Pages serves it."
