// Where the wait goes when a level starts in the web build, phase by phase, in the
// container's Chromium (WebGL2 on SwiftShader, the engine's wasm single-threaded).
//
//   $GODOT --headless --path . --export-release "Web" /some/dir/index.html
//   node game/streets/tests/web_load.js /some/dir [level]
//
// Goes straight into the level by the shell's self-play args (no menu), and prints when the
// engine was up, when the city file was read, when the squares round the start were built
// (with every stage's ms so far, `_stage_ms`, slowest first), and when the warm-up was
// done: the moment the car can be driven. The files are served from localhost, so downloading costs nothing here --
// on a phone after a publish that is index.pck's 39 MB on top (see tools/publish_web.sh).
//
// SwiftShader draws in software: the warm-up (shader compiling plus twelve frames of the
// town) and any stage that draws frames ("far shadows") are many times a real GPU's. The
// CPU stages (city file, kerbs, roads...) are the wasm's own cost, and in proportion.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const dir = process.argv[2];
const level = process.argv[3] || '1';
if (!dir || !fs.existsSync(path.join(dir, 'index.html'))) {
  console.error('usage: node web_load.js <exported web dir> [level]');
  process.exit(1);
}
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const f = path.join(dir, p);
  if (!f.startsWith(path.resolve(dir)) || !fs.existsSync(f)) { res.writeHead(404); res.end(); return; }
  let body = fs.readFileSync(f);
  if (p === '/index.html') {   // straight into the level, no worker (it would cache across runs)
    body = body.toString().replace('"args":[]', `"args":["--","--sim=streets","--bot=idle","--seconds=600","--level=${level}"]`)
      .replace('"serviceWorker":SW_URL', '"serviceWorker":""')
      .replace('"serviceWorker":"index.service.worker.js"', '"serviceWorker":""');
  }
  res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream',
    'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' });
  res.end(body);
});

(async () => {
  await new Promise((ok) => server.listen(0, ok));
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--ignore-gpu-blocklist', '--enable-webgl'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const t0 = Date.now();
  const mark = (s) => console.log(`${((Date.now() - t0) / 1000).toFixed(1).padStart(6)} s  ${s}`);
  let done = false;
  page.on('console', (m) => {
    const t = m.text();
    if (/SCRIPT ERROR|USER ERROR/.test(t)) mark('game: ' + t.split('\n')[0]);
    if (!t.startsWith('[streets]')) return;
    if (t.startsWith('[streets] warm-up done')) done = true;
    const i = t.indexOf('; stages ');
    if (i < 0) { mark(t); return; }
    mark(t.slice(0, i));
    const st = JSON.parse(t.slice(i + 9));
    Object.entries(st).sort((a, b) => b[1] - a[1]).forEach(([k, v]) => console.log(`${String(v).padStart(14)} ms  ${k}`));
  });
  await page.goto(`http://localhost:${server.address().port}/`);
  mark('page loaded');
  await page.waitForFunction(() => {
    const s = document.getElementById('status');
    return !s || s.style.display === 'none' || getComputedStyle(s).visibility === 'hidden';   // (Godot removes it)
  }, null, { timeout: 120000 }).catch(() => {});
  mark('engine up (splash gone)');
  const limit = Date.now() + 900000;
  while (!done && Date.now() < limit) await page.waitForTimeout(500);
  mark(done ? 'the car can be driven' : 'gave up waiting');
  await browser.close();
  server.close();
})();
