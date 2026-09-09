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

# Godot's service worker is cache-first with no revalidation, and the replacement worker
# never calls skipWaiting -- so an installed app serves the old build forever and even a
# refresh does not help, because the refreshed page is still controlled by the old worker.
# Patch it to take over immediately and reload open windows onto the new build.
#
# Second problem, found once the first was fixed: GitHub Pages serves everything with
# Cache-Control: max-age=600, and the worker fetched index.pck with a plain fetch(). So a
# NEW worker, installing within ten minutes of a publish, was handed the PREVIOUS pck by
# the HTTP cache (or the CDN edge) and locked it into its versioned cache -- until the next
# publish. Phones, which tend to open the game right after a push, hit this every time.
# Every fetch the worker may cache now goes out under a URL stamped with the build's
# version and cache:'no-store', so neither cache can answer it.
python - <<'SW'
import io
p = 'docs/index.service.worker.js'
s = io.open(p, encoding='utf-8').read()

def swap(old, new, what):
    global s
    assert old in s, what + ' not as expected -- Godot changed its template'
    s = s.replace(old, new, 1)

swap("""self.addEventListener('install', (event) => {
	event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)));
});""",
"""// PATCHED by tools/publish_web.sh -- fetch straight from the origin, under a URL stamped
// with this build's version and with the HTTP cache switched off. Otherwise a freshly
// installed worker can be handed the PREVIOUS build's index.pck by the browser cache or the
// GitHub Pages CDN (Cache-Control: max-age=600) and lock it in until the next publish.
function freshFetch(url) {
	const u = new URL(url, self.location.href);
	u.searchParams.set('v', CACHE_VERSION);
	return self.fetch(u.href, { cache: 'no-store', credentials: 'same-origin' });
}

self.addEventListener('install', (event) => {
	// PATCHED by tools/publish_web.sh -- precache with freshFetch, then take over instead of
	// waiting for every window to close first.
	event.waitUntil((async () => {
		const cache = await caches.open(CACHE_NAME);
		await Promise.all(CACHED_FILES.map(async (f) => {
			const res = await freshFetch(f);
			if (res.ok) {
				await cache.put(f, res);
			}
		}));
		await self.skipWaiting();
	})());
});""", 'install handler')

start = s.index("self.addEventListener('activate'")
end = s.index('/**', start)
new_activate = """self.addEventListener('activate', (event) => {
	// PATCHED by tools/publish_web.sh -- claim the open pages, and if this build replaced
	// an older one, reload them onto it. Guarded on there having BEEN an older one, so a
	// first install (or a re-registration of the same build) does not reload for nothing.
	event.waitUntil((async () => {
		const keys = await caches.keys();
		const stale = keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME);
		await Promise.all(stale.map((key) => caches.delete(key)));
		await self.clients.claim();
		if (stale.length > 0) {
			const all = await self.clients.matchAll({ type: 'window' });
			all.forEach((c) => c.navigate(c.url));
		}
	})());
});

"""
s = s[:start] + new_activate + s[end:]

swap("""	// Use the preloaded response, if it's there
	/** @type { Response } */
	let response = await event.preloadResponse;
	if (response == null) {
		// Or, go over network.
		response = await self.fetch(event.request);
	}
""",
"""	// PATCHED by tools/publish_web.sh -- always the stamped, uncached fetch (freshFetch above).
	let response = await freshFetch(event.request.url);
""", 'fetchAndCache')

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('service worker: patched for immediate takeover and cache-proof fetches')
SW

# The browser only looks for a new worker at the URL it was registered under, and GitHub
# Pages' CDN may answer that with the old worker for up to ten minutes. Register under a
# URL that changes every minute instead, as early in the page as possible and again when
# the app comes back to the foreground, so a publish shows up within about a minute.
python - <<'HTML'
import io
p = 'docs/index.html'
s = io.open(p, encoding='utf-8').read()
old_cfg = '"serviceWorker":"index.service.worker.js"'
assert old_cfg in s, 'GODOT_CONFIG not as expected -- Godot changed its template'
s = s.replace(old_cfg, '"serviceWorker":SW_URL', 1)   # so the engine registers the same URL
head = """<script>
// PATCHED by tools/publish_web.sh -- register the service worker under a URL that changes
// every minute. The browser checks for a new worker at the registered URL, and the GitHub
// Pages CDN (max-age=600) would otherwise keep answering with the previous build's worker
// for up to ten minutes. Registered here, before the engine loads, and again whenever the
// app returns to the foreground. GODOT_CONFIG below points the engine at the same URL, so
// the two registrations never fight over which worker is current.
const SW_URL = 'index.service.worker.js?t=' + Math.floor(Date.now() / 60000);
if ('serviceWorker' in navigator) {
	const lookForNewBuild = (url) => navigator.serviceWorker.register(url).catch(() => {});
	lookForNewBuild(SW_URL);
	document.addEventListener('visibilitychange', () => {
		if (document.visibilityState === 'visible') {
			lookForNewBuild('index.service.worker.js?t=' + Math.floor(Date.now() / 60000));
		}
	});
}
</script>
"""
assert '</head>' in s
s = s.replace('</head>', head + '</head>', 1)
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('index.html: registers a minute-stamped worker URL on load and on foreground')
HTML

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
