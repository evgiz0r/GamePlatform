// Does a returning visitor download the engine again after a publish? It should not:
// tools/publish_web.sh patches the service worker to copy index.wasm out of the old
// build's cache when its SHA-256 matches. This loads build A, lets its worker cache
// everything, then "publishes" build B (the same files, a new cache version and a changed
// index.pck) and counts what the browser fetches from the server.
//
//   tools/publish_web.sh                       # or any docs/ it produced
//   node tools/pwa/reuse_test.js docs
//
// Good: B downloads index.pck once and index.wasm not at all. ~2 min (it waits for the
// minute to turn over: the page looks for a new worker under a minute-stamped URL).
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { chromium } = require('playwright');

const src = process.argv[2];
if (!src || !fs.existsSync(path.join(src, 'index.service.worker.js'))) {
  console.error('usage: node tools/pwa/reuse_test.js <published docs dir>');
  process.exit(1);
}
// build B: a copy with another cache version and a different pck (trailing bytes, harmless)
const b = fs.mkdtempSync(path.join(os.tmpdir(), 'reuse-b-'));
for (const f of fs.readdirSync(src)) {
  if (fs.statSync(path.join(src, f)).isFile()) fs.copyFileSync(path.join(src, f), path.join(b, f));
}
const sw = fs.readFileSync(path.join(b, 'index.service.worker.js'), 'utf8');
const swB = sw.replace(/const CACHE_VERSION = '[^']*';/, "const CACHE_VERSION = 'reuse-test-b';");
if (swB === sw) { console.error('no CACHE_VERSION in the worker'); process.exit(1); }
fs.writeFileSync(path.join(b, 'index.service.worker.js'), swB);
fs.appendFileSync(path.join(b, 'index.pck'), Buffer.alloc(16));

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

(async () => {
  await new Promise((ok) => server.listen(0, ok));
  const url = `http://localhost:${server.address().port}/`;
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await (await browser.newContext()).newPage();
  page.on('console', (m) => { if (/not reused/.test(m.text())) console.log('  page: ' + m.text().slice(0, 200)); });
  const cached = () => page.evaluate(async () => {
    const out = {};
    for (const k of await caches.keys()) out[k] = (await (await caches.open(k)).keys()).map((r) => r.url.split('/').pop()).sort().join(' ');
    return out;
  }).catch((e) => 'could not read the caches: ' + e.message);
  await page.goto(url);
  await wait(12000);
  await page.reload();   // controlled by A's worker now: the engine and the pck go into its cache
  await wait(12000);
  console.log('A cached:   ', JSON.stringify(await cached()));
  for (const k of Object.keys(hits)) delete hits[k];
  current = 'b';
  await wait(61000 - (Date.now() % 60000));
  await page.reload().catch(() => {});
  await wait(25000);
  console.log('B cached:   ', JSON.stringify(await cached()));
  console.log('B downloads:', JSON.stringify(hits));
  const ok = (hits['/index.wasm'] || 0) === 0 && (hits['/index.pck'] || 0) === 1;
  console.log(ok ? 'PASS: the engine came from the old cache, the pck from the server' : 'FAIL: see the downloads above');
  await browser.close();
  server.close();
  fs.rmSync(b, { recursive: true, force: true });
  process.exit(ok ? 0 : 1);
})();
