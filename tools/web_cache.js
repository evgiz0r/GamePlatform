// What a phone downloads after a publish: serves one web build, opens it with its service
// worker (as a player's browser has it), then swaps in a second build at the same address,
// and lists every file the browser fetched from the server for each, with its size.
//
//   node tools/web_cache.js <first build dir> <second build dir>
//
// Make the two with tools/publish_web.sh twice (copying docs/ away between), changing
// whatever you want to measure in between -- or nothing: build.txt changes every build, so
// the main pack always differs. With the split packs (tools/split_pck.py) the second build
// should fetch index.pck and the small files only, unless art, sound or a data file changed.
// The page is opened at the menu (no args); "running" is the splash gone.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const dirs = [process.argv[2], process.argv[3]];
if (!dirs[0] || !dirs[1]) {
  console.error('usage: node tools/web_cache.js <first build dir> <second build dir>');
  process.exit(1);
}
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };
let dir = dirs[0];
let served = [];
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const f = path.join(dir, p);
  if (!f.startsWith(path.resolve(dir)) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) {
    res.writeHead(404); res.end(); return;
  }
  const body = fs.readFileSync(f);
  served.push([p.slice(1), body.length]);
  res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream',
    'Cache-Control': 'max-age=600',   // as GitHub Pages serves it
    'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' });
  res.end(body);
});

const report = (what) => {
  const by = {};
  for (const [f, n] of served) by[f] = (by[f] || 0) + n;
  const total = Object.values(by).reduce((a, b) => a + b, 0);
  console.log(`--- ${what}: ${(total / 1e6).toFixed(2)} MB from the server`);
  Object.entries(by).sort((a, b) => b[1] - a[1])
    .forEach(([f, n]) => console.log(`${(n / 1e6).toFixed(2).padStart(9)} MB  ${f}`));
  served = [];
};

(async () => {
  await new Promise((ok) => server.listen(0, ok));
  const url = `http://localhost:${server.address().port}/`;
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--ignore-gpu-blocklist', '--enable-webgl'] });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await ctx.newPage();
  page.on('console', (m) => { if (/ERROR|pack not/.test(m.text())) console.log('page: ' + m.text().split('\n')[0]); });
  page.on('pageerror', (e) => console.log('page error: ' + e.message));
  const running = async (what) => {
    const t0 = Date.now();
    await page.waitForFunction(() => {
      const s = document.getElementById('status');
      return !s || getComputedStyle(s).display === 'none' || s.style.visibility === 'hidden';
    }, null, { timeout: 600000 });
    console.log(`${what}: running after ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  };

  // a first visit: the page reloads itself once the worker is in, then the build is cached
  await page.goto(url);
  await running('first build, first visit');
  await page.waitForTimeout(3000);
  report('first build, first visit');

  await page.reload();
  await running('first build, second visit');
  await page.waitForTimeout(2000);
  report('first build, second visit (should be nothing big)');

  // a publish: the next look for a new worker finds the second build; it fetches what it
  // lacks in the background, takes over and the page is offered (or given) the restart
  dir = dirs[1];
  const swapped = page.waitForEvent('framenavigated', { timeout: 600000 }).catch(() => null);
  await page.evaluate(() => navigator.serviceWorker.register('index.service.worker.js?t=' + Date.now()));
  await page.waitForFunction(() => document.getElementById('new-build') !== null
    || !!(navigator.serviceWorker.controller && navigator.serviceWorker.controller.scriptURL), null, { timeout: 600000 });
  for (let i = 0; i < 600 && !(await page.$('#new-build')); i++) await page.waitForTimeout(500);
  console.log((await page.$('#new-build')) ? 'second build: "new version ready" offered' : 'second build: no offer seen');
  await page.reload();
  await running('second build');
  await page.waitForTimeout(2000);
  report('second build (what a publish costs)');
  void swapped;
  await browser.close();
  server.close();
})().catch((e) => { console.error(e); process.exit(1); });
