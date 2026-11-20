// How a returning player meets a new build, in the container's Chromium. tools/publish_web.sh
// patches Godot's service worker and page so that:
//   - a first visit downloads index.wasm and index.pck once (through the worker, into its cache);
//   - after a publish, the build already on the device starts at once (nothing downloaded
//     before it plays), while the new build downloads in the background -- index.pck only,
//     the engine copied from the old cache when its SHA-256 matches;
//   - the page is never reloaded under the player: it offers "new version ready, tap to
//     restart", and the restart starts the new build with nothing left to download.
//
//   tools/publish_web.sh                       # or any docs/ it produced
//   node tools/pwa/update_test.js docs
//
// Build B is a copy of the given build with another cache version and a changed index.pck.
// ~2 min (it waits for the minute to turn over: the page looks for a new worker under a
// minute-stamped URL). Prints PASS or FAIL per check; exits 1 on any FAIL. SHOT=file.png saves
// the page with the restart offer on it.
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { chromium } = require('playwright');

const src = process.argv[2];
if (!src || !fs.existsSync(path.join(src, 'index.service.worker.js'))) {
  console.error('usage: node tools/pwa/update_test.js <published docs dir>');
  process.exit(1);
}
const b = fs.mkdtempSync(path.join(os.tmpdir(), 'update-b-'));
for (const f of fs.readdirSync(src)) {
  if (fs.statSync(path.join(src, f)).isFile()) fs.copyFileSync(path.join(src, f), path.join(b, f));
}
const sw = fs.readFileSync(path.join(b, 'index.service.worker.js'), 'utf8');
const swB = sw.replace(/const CACHE_VERSION = '[^']*';/, "const CACHE_VERSION = 'update-test-b';");
if (swB === sw) { console.error('no CACHE_VERSION in the worker'); process.exit(1); }
fs.writeFileSync(path.join(b, 'index.service.worker.js'), swB);
fs.appendFileSync(path.join(b, 'index.pck'), Buffer.alloc(16));   // (trailing bytes: harmless)

const dirs = { a: path.resolve(src), b };
let current = 'a';
const hits = {};
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const f = path.join(dirs[current], p);
  hits[p] = (hits[p] || 0) + 1;
  if (!f.startsWith(dirs[current]) || !fs.existsSync(f)) { res.writeHead(404); res.end(); return; }
  // as GitHub Pages: ten minutes of HTTP cache, no cross-origin headers (the worker adds them)
  res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'max-age=600' });
  res.end(fs.readFileSync(f));
});
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = 0;
const check = (ok, what) => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}`); if (!ok) failed += 1; };
const big = () => `wasm ${hits['/index.wasm'] || 0}, pck ${hits['/index.pck'] || 0}`;
const reset = () => { for (const k of Object.keys(hits)) delete hits[k]; };

(async () => {
  await new Promise((ok) => server.listen(0, ok));
  const url = `http://localhost:${server.address().port}/`;
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await (await browser.newContext()).newPage();
  let navs = 0;
  page.on('framenavigated', (fr) => { if (fr === page.mainFrame()) navs += 1; });
  page.on('console', (m) => { if (/not reused|Error while/.test(m.text())) console.log('  page: ' + m.text().slice(0, 200)); });
  const cached = () => page.evaluate(async () => {
    const out = {};
    for (const k of await caches.keys()) out[k] = (await (await caches.open(k)).keys()).length;
    return out;
  }).catch((e) => ({ error: e.message }));
  // the engine is running once Godot has taken its splash away
  const engineUp = async () => {
    const t = Date.now();
    await page.waitForFunction(() => !document.getElementById('status'), null, { timeout: 60000 }).catch(() => {});
    return Date.now() - t;
  };

  // 1. first visit
  await page.goto(url);
  await engineUp();
  await wait(4000);
  console.log(`first visit: ${big()}, caches ${JSON.stringify(await cached())}`);
  check(hits['/index.wasm'] === 1 && hits['/index.pck'] === 1, 'a first visit downloads the engine and the pck once each');
  const a = await cached();
  check(Object.values(a).length === 1 && Object.values(a)[0] === 9, 'and keeps all nine files');

  // 2. a publish; the player comes back
  reset();
  current = 'b';
  await wait(61000 - (Date.now() % 60000));
  navs = 0;
  await page.reload();
  const upMs = await engineUp();
  const navsAtUp = navs;
  console.log(`back after a publish: a build up in ${upMs} ms, navigations ${navsAtUp}`);
  check(navsAtUp === 1 && upMs < 20000, 'the build already here starts at once (no reload onto the new one first)');
  let pill = false;
  for (let i = 0; i < 60 && !pill; i += 1) {
    await wait(1000);
    pill = await page.evaluate(() => !!document.getElementById('new-build'));
  }
  console.log(`new build fetched in the background: ${big()}, caches ${JSON.stringify(await cached())}, navigations ${navs}`);
  check(pill, '"new version ready, tap to restart" is offered');
  if (pill && process.env.SHOT) await page.screenshot({ path: process.env.SHOT });   // (SHOT=file.png: what it looks like)
  check(navs === 1, 'the page was not reloaded under the player');
  check((hits['/index.wasm'] || 0) === 0 && hits['/index.pck'] === 1, 'only index.pck was downloaded (the engine kept)');

  // 3. the tap
  reset();
  navs = 0;
  if (pill) await page.click('#new-build');
  await page.waitForLoadState('load').catch(() => {});
  const upB = await engineUp();
  await wait(2000);
  const c = await cached();
  console.log(`after the tap: up in ${upB} ms, ${big()} downloaded, caches ${JSON.stringify(c)}`);
  check(navs >= 1 && (hits['/index.wasm'] || 0) === 0 && (hits['/index.pck'] || 0) === 0, 'the restart starts the new build with nothing to download');
  check(Object.keys(c).length === 1 && Object.keys(c)[0].endsWith('update-test-b'), 'only the new build is left in the caches');

  await browser.close();
  server.close();
  fs.rmSync(b, { recursive: true, force: true });
  console.log(failed ? `${failed} FAILED` : 'all passed');
  process.exit(failed ? 1 : 0);
})();
