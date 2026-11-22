// This service worker is required to expose an exported Godot project as a
// Progressive Web App. It provides an offline fallback page telling the user
// that they need an Internet connection to run the project if desired.
// Incrementing CACHE_VERSION will kick off the install event and force
// previously cached resources to be updated from the network.
/** @type {string} */
const CACHE_VERSION = '1795359208|5075398';
/** @type {string} */
const CACHE_PREFIX = 'GamePlatform-sw-cache-';
const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;
/** @type {string} */
const OFFLINE_URL = 'index.offline.html';
/** @type {boolean} */
const ENSURE_CROSSORIGIN_ISOLATION_HEADERS = true;
// Files that will be cached on load.
/** @type {string[]} */
const CACHED_FILES = ["index.html","index.js","index.offline.html","index.icon.png","index.apple-touch-icon.png","index.audio.worklet.js","index.audio.position.worklet.js"];
// Files that we might not want the user to preload, and will only be cached on first load.
/** @type {string[]} */
const CACHEABLE_FILES = ["index.wasm","index.pck","index.art.f6e9adab12ec.pck","index.data_annecy.4fd580197180.pck","index.data_ashdod.b73f2db1e049.pck","index.data_bedford.00e1e1f51859.pck","index.data_delft.9e06d21a3cd1.pck","index.data_dimyon.2040101ccaa2.pck","index.data_givatayim.b1ff12e93337.pck","index.data_leiden.985cd529d9cf.pck","index.data_tel_aviv.7adb3afa8446.pck","index.sound.1e5ae9778cac.pck"];
const FULL_CACHE = CACHED_FILES.concat(CACHEABLE_FILES);

// PATCHED by tools/publish_web.sh -- fetch straight from the origin, under a URL stamped
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
			await reusePacks(cache);
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
const WASM_SHA256 = '7eda98958eb09135a1acb54a4323a00b1a55af1997f15fa1cdc2b93e3df46656';
// PATCHED by tools/publish_web.sh -- a split pack's name is its content hash, so an older
// build's copy under the same name is this build's file: take it instead of downloading it.
async function reusePacks(cache) {
	for (const f of CACHEABLE_FILES) {
		if (!/^index\..+\.pck$/.test(f) || (await cache.match(f)) !== undefined) {
			continue;
		}
		for (const key of await caches.keys()) {
			if (!key.startsWith(CACHE_PREFIX) || key === CACHE_NAME) {
				continue;
			}
			const old = await (await caches.open(key)).match(f);
			if (old) {
				await cache.put(f, old);
				break;
			}
		}
	}
}

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
}

self.addEventListener('activate', (event) => {
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

/**
 * Ensures that the response has the correct COEP/COOP headers
 * @param {Response} response
 * @returns {Response}
 */
function ensureCrossOriginIsolationHeaders(response) {
	if (response.headers.get('Cross-Origin-Embedder-Policy') === 'require-corp'
		&& response.headers.get('Cross-Origin-Opener-Policy') === 'same-origin') {
		return response;
	}

	const crossOriginIsolatedHeaders = new Headers(response.headers);
	crossOriginIsolatedHeaders.set('Cross-Origin-Embedder-Policy', 'require-corp');
	crossOriginIsolatedHeaders.set('Cross-Origin-Opener-Policy', 'same-origin');
	const newResponse = new Response(response.body, {
		status: response.status,
		statusText: response.statusText,
		headers: crossOriginIsolatedHeaders,
	});

	return newResponse;
}

/**
 * Calls fetch and cache the result if it is cacheable
 * @param {FetchEvent} event
 * @param {Cache} cache
 * @param {boolean} isCacheable
 * @returns {Response}
 */
async function fetchAndCache(event, cache, isCacheable) {
	// PATCHED by tools/publish_web.sh -- always the stamped, uncached fetch (freshFetch above).
	let response = await freshFetch(event.request.url);

	if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
		response = ensureCrossOriginIsolationHeaders(response);
	}

	if (isCacheable) {
		// And update the cache
		cache.put(event.request, response.clone());
	}

	return response;
}

self.addEventListener(
	'fetch',
	/**
	 * Triggered on fetch
	 * @param {FetchEvent} event
	 */
	(event) => {
		const isNavigate = event.request.mode === 'navigate';
		const url = event.request.url || '';
		const referrer = event.request.referrer || '';
		const base = referrer.slice(0, referrer.lastIndexOf('/') + 1);
		const local = url.startsWith(base) ? url.replace(base, '') : '';
		const isCacheable = FULL_CACHE.some((v) => v === local) || (base === referrer && base.endsWith(CACHED_FILES[0]));
		if (isNavigate || isCacheable) {
			event.respondWith((async () => {
				// Try to use cache first
				const cache = await caches.open(CACHE_NAME);
				if (isNavigate) {
					// Check if we have full cache during HTML page request.
					/** @type {Response[]} */
					const fullCache = await Promise.all(FULL_CACHE.map((name) => cache.match(name)));
					const missing = fullCache.some((v) => v === undefined);
					if (missing) {
						try {
							// Try network if some cached file is missing (so we can display offline page in case).
							const response = await fetchAndCache(event, cache, isCacheable);
							return response;
						} catch (e) {
							// And return the hopefully always cached offline page in case of network failure.
							console.error('Network error: ', e); // eslint-disable-line no-console
							return caches.match(OFFLINE_URL);
						}
					}
				}
				let cached = await cache.match(event.request);
				if (cached != null) {
					if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
						cached = ensureCrossOriginIsolationHeaders(cached);
					}
					return cached;
				}
				// Try network if don't have it in cache.
				const response = await fetchAndCache(event, cache, isCacheable);
				return response;
			})());
		} else if (ENSURE_CROSSORIGIN_ISOLATION_HEADERS) {
			event.respondWith((async () => {
				let response = await fetch(event.request);
				response = ensureCrossOriginIsolationHeaders(response);
				return response;
			})());
		}
	}
);

self.addEventListener('message', (event) => {
	// No cross origin
	if (event.origin !== self.origin) {
		return;
	}
	const id = event.source.id || '';
	const msg = event.data || '';
	// Ensure it's one of our clients.
	self.clients.get(id).then(function (client) {
		if (!client) {
			return; // Not a valid client.
		}
		if (msg === 'claim') {
			self.skipWaiting().then(() => self.clients.claim());
		} else if (msg === 'clear') {
			caches.delete(CACHE_NAME);
		} else if (msg === 'update') {
			self.skipWaiting().then(() => self.clients.claim()).then(() => self.clients.matchAll()).then((all) => all.forEach((c) => c.navigate(c.url)));
		}
	});
});

