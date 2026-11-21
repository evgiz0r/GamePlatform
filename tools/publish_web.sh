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

# A game can work things out once per build instead of on every player's load: its
# game/<name>/prepublish.gd (a SceneTree script) runs here, headless, and what it writes under
# game/<name>/baked/ ships in this build (export_presets.cfg includes game/*/baked/*). Made
# again for every build, from that build's code (it can stamp it with build.txt, written just
# above), never committed (.gitignore), and removed after the export. A prepublish that fails
# or runs out of time only costs the build its shortcut: the game works it out as before.
rm -rf game/*/baked
for pp in game/*/prepublish.gd; do
  [ -f "$pp" ] || continue
  timeout 900 "$BIN" --headless --path . -s "res://$pp" 2>&1 | grep -v '^$' || echo "prepublish $pp failed: the build goes without what it bakes"
done

mkdir -p docs
"$BIN" --headless --path . --export-release "Web" docs/index.html
rm -rf game/*/baked

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
#
# Third: a new cache per build meant every publish (dozens a day while a game is being
# worked on) sent a phone back for all 78 MB, the engine's 39 MB included, though that
# file only changes with the Godot version. The new worker now copies the engine out of
# the old build's cache when its SHA-256 matches, so a publish costs index.pck alone.
#
# Fourth (user: "sometimes 3 seconds, sometimes 20"): a new build used to take over at
# once and reload the page, which then waited for index.pck to download. Now the build
# already on the device starts at once and the new one downloads in the background while
# it plays: its worker only takes over once it holds every file, and then nothing is
# reloaded under the player -- the page offers "new version ready, tap to restart" (or
# reloads by itself if the old build was still on its splash screen), and the next launch
# is the new build either way. A first visit (no build on the device yet) still waits for
# its download, as it must.
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
	// waiting for every window to close first. When an older build is on the device (it
	// plays meanwhile), the whole new build is fetched first -- the engine copied across if
	// unchanged, index.pck downloaded -- so the switch to it never waits for a download.
	// A first install takes over at once: the page's own first load fills its cache.
	// (Files already in this build's cache are kept: an install cut short resumes.)
	event.waitUntil((async () => {
		const cache = await caches.open(CACHE_NAME);
		const have = async (f) => (await cache.match(f)) !== undefined;
		await Promise.all(CACHED_FILES.map(async (f) => {
			if (await have(f)) {
				return;
			}
			const res = await freshFetch(f);
			if (res.ok) {
				await cache.put(f, res);
			}
		}));
		const older = (await caches.keys()).some((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME);
		if (older) {
			if (!(await have('index.wasm'))) {
				await reuseEngine(cache);
			}
			for (const f of CACHEABLE_FILES) {
				if (await have(f)) {
					continue;
				}
				const res = await freshFetch(f);
				if (!res.ok) {
					throw new Error(f + ': ' + res.status);   // (the old build stays; tried again at the next check)
				}
				await cache.put(f, res);
			}
		}
		await self.skipWaiting();
	})());
});

// PATCHED by tools/publish_web.sh -- the engine (index.wasm, ~39 MB) only changes with the
// Godot version, yet every publish starts a new cache and so downloaded it again. If an
// older build's cache holds the very same file (by its SHA-256, WASM_SHA256 below), copy it
// across before the old caches are dropped: only index.pck is downloaded after a publish.
const WASM_SHA256 = '@WASM_SHA256@';
async function reuseEngine(cache) {
	try {
		for (const key of await caches.keys()) {
			if (!key.startsWith(CACHE_PREFIX) || key === CACHE_NAME) {
				continue;
			}
			const old = await (await caches.open(key)).match('index.wasm');
			if (!old) {
				continue;
			}
			const keep = old.clone();
			const sum = await crypto.subtle.digest('SHA-256', await old.arrayBuffer());
			const hex = Array.from(new Uint8Array(sum), (b) => b.toString(16).padStart(2, '0')).join('');
			if (hex === WASM_SHA256) {
				await cache.put('index.wasm', keep);
				return;
			}
		}
	} catch (e) {
		console.warn('engine not reused from an older build: ', e); // eslint-disable-line no-console
	}
}""", 'install handler')

import hashlib
wasm_sha = hashlib.sha256(open('docs/index.wasm', 'rb').read()).hexdigest()
s = s.replace('@WASM_SHA256@', wasm_sha, 1)

start = s.index("self.addEventListener('activate'")
end = s.index('/**', start)
new_activate = """self.addEventListener('activate', (event) => {
	// PATCHED by tools/publish_web.sh -- claim the open pages, and if this build replaced
	// an older one, tell them: the page offers a restart onto it (index.html's 'new-build'
	// listener) instead of being reloaded under the player. Guarded on there having BEEN an
	// older one, so a first install (or a re-registration of the same build) says nothing.
	event.waitUntil((async () => {
		const keys = await caches.keys();
		const stale = keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME);
		await Promise.all(stale.map((key) => caches.delete(key)));
		await self.clients.claim();
		if (stale.length > 0) {
			const all = await self.clients.matchAll({ type: 'window' });
			all.forEach((c) => c.postMessage({ type: 'new-build' }));
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
print('service worker: patched for background updates, a kept engine and cache-proof fetches')
SW

# The browser only looks for a new worker at the URL it was registered under, and GitHub
# Pages' CDN may answer that with the old worker for up to ten minutes. Register under a
# URL that changes every minute instead, as early in the page as possible and again when
# the app comes back to the foreground, so a publish shows up within about a minute.
# The page also offers the restart onto a new build once its worker has all of it (see
# "Fourth" above), and on a first visit holds the engine back until the worker controls
# the page, so the two big files go into its cache instead of being downloaded twice.
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
	// a new build is on the device (its worker fetched all of it in the background): still
	// on the splash, nothing to lose -- reload onto it; playing, offer it, never force it
	navigator.serviceWorker.addEventListener('message', (e) => {
		if (!e.data || e.data.type !== 'new-build') {
			return;
		}
		if (document.getElementById('status')) {   // (Godot removes the splash once running)
			window.location.reload();
			return;
		}
		if (document.getElementById('new-build')) {
			return;
		}
		const b = document.createElement('div');
		b.id = 'new-build';
		b.textContent = 'new version ready \u2014 tap to restart';
		b.style.cssText = 'position:fixed;top:6px;left:50%;transform:translateX(-50%);z-index:10;'
			+ 'padding:6px 4px 6px 14px;border-radius:16px;background:rgba(8,8,20,0.85);color:#fff;'
			+ 'border:1px solid rgba(110,220,255,0.85);box-shadow:0 0 10px rgba(110,220,255,0.5);'
			+ 'font:14px sans-serif;white-space:nowrap;cursor:pointer;user-select:none;-webkit-user-select:none';
		b.addEventListener('click', () => window.location.reload());
		const x = document.createElement('span');   // (later: the next launch is the new build anyway)
		x.textContent = '\u00d7';
		x.style.cssText = 'margin-left:6px;padding:0 10px;opacity:0.7';
		x.addEventListener('click', (e2) => {
			e2.stopPropagation();
			b.remove();
		});
		b.appendChild(x);
		document.body.appendChild(b);
	});
}
// a first visit: no worker controls the page yet, so the engine would fetch its two big files
// past it, uncached, and the next visit would download them again. Wait for the worker to
// take the page over (a second or so; at most 4) so they go into its cache on the way.
const SW_READY = (!('serviceWorker' in navigator) || navigator.serviceWorker.controller) ? Promise.resolve()
	: new Promise((ok) => {
		navigator.serviceWorker.addEventListener('controllerchange', () => ok(), { once: true });
		setTimeout(ok, 4000);
	});
</script>
"""
assert '</head>' in s
s = s.replace('</head>', head + '</head>', 1)
for old, new in [('\t\tengine.startGame({', '\t\tSW_READY.then(() => engine.startGame({'),
                 ("\t\t}).then(() => {\n\t\t\tsetStatusMode('hidden');", "\t\t})).then(() => {\n\t\t\tsetStatusMode('hidden');")]:
    assert s.count(old) == 1, 'engine start not as expected -- Godot changed its template'
    s = s.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('index.html: minute-stamped worker URL, restart offered on a new build, first visit cached')
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
