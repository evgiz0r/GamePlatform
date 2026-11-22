// The shaders a browser compiles for the streets game, counted in the browser itself.
//
// A browser compiles each shader program the first time something is drawn with it, and each
// one stalls that frame -- tens to hundreds of ms on a phone or through ANGLE on Windows. The
// game draws every kind of surface once behind the loading text (_warm_up) so this happens
// there and not while you drive. This runs a web export in the container's Chromium (WebGL2
// on SwiftShader), straight into a level by the shell's self-play args, and counts the
// programs linked before the warm-up, during it, and after it (each of those a stall while
// playing), with their time on SwiftShader (slow, but in proportion).
//
//   $GODOT --headless --path . --export-release "Web" /some/dir/index.html
//   node game/streets/tests/web_shaders.js /some/dir [level] [seconds of play]
//
// DUMP=file.json also writes every program's source (vertex + fragment, in link order) to compare
// two builds with tests/shader_diff.py: a browser keeps the programs it compiled (its program
// cache, keyed by the source), so a publish that leaves the GLSL as it was costs a phone no
// compiling, and one that changes it costs the whole warm-up again.
// TIMES=n clicks the time-of-day button n times once the play's seconds are up (GAP seconds
// apart, default 40) and lists the programs each click made the browser compile, by material
// and variant: what to warm up ahead so the button does not hang. BOT=idle leaves the car
// standing (the smart bot's driving got the second click lost).
// QWALK=S walks the quality levels instead (the game's --quality-walk: 1, 0, 1, 2, 3, 2, S seconds
// apart after the warm-up, the ladder held off) and lists the programs each step compiled: a
// step should cost a handful (a resolve or blit), never a set per material -- each program
// is ~0.13-0.4 s on a Windows laptop's first visit (a work laptop froze 13.7 s once, 22 Nov).
// Needs the build's own files only (served here with the cross-origin headers the threaded
// build needs). Prints the counts and the slowest programs' moments; exits when the game
// prints its report or after the seconds run out.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const dir = process.argv[2];
const level = process.argv[3] || '1';
const seconds = Number(process.argv[4] || '20');
const times = Number(process.env.TIMES || '0');
const gap = Number(process.env.GAP || '40');
const qwalk = Number(process.env.QWALK || '0');
if (!dir || !fs.existsSync(path.join(dir, 'index.html'))) {
  console.error('usage: node web_shaders.js <exported web dir> [level] [seconds]');
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
  if (p === '/index.html') {   // straight into the level, playing itself (shell/autoload/flow.gd)
    body = body.toString().replace('"args":[]',
      `"args":["--","--sim=streets","--bot=${process.env.BOT || 'smart'}","--seconds=${seconds + (times ? times * gap + 120 : 0) + (qwalk ? 7 * qwalk + 120 : 0)}","--level=${level}"${qwalk ? `,"--quality-walk=${qwalk}"` : ''}]`)
      .replace('"serviceWorker":SW_URL', '"serviceWorker":""');
  }
  res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream',
    'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' });
  res.end(body);
});

(async () => {
  await new Promise((ok) => server.listen(0, ok));
  const port = server.address().port;
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--ignore-gpu-blocklist', '--enable-webgl'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  if (process.env.DUMP) await page.addInitScript(() => { window.__dump = true; });
  await page.addInitScript(() => {
    // every compile and link, and the status checks after them (where a driver that compiles
    // in the background makes the caller wait), timed
    const P = WebGL2RenderingContext.prototype;
    const log = (window.__gl = { links: [], compiles: 0, ms: 0 });
    const wrap = (name, after) => {
      const orig = P[name];
      P[name] = function (...a) {
        const t = performance.now();
        const r = orig.apply(this, a);
        const dt = performance.now() - t;
        log.ms += dt;
        after(t, dt);
        return r;
      };
    };
    const cms = new WeakMap();   // each shader's own compile time, put to its program at link
    const cs = P.compileShader;
    P.compileShader = function (sh) { const t = performance.now(); const r = cs.call(this, sh); cms.set(sh, performance.now() - t); return r; };
    // (a browser compiles in the background: the wait lands on the status check after it)
    const gsp = P.getShaderParameter;
    P.getShaderParameter = function (sh, p) { const t = performance.now(); const r = gsp.call(this, sh, p); cms.set(sh, (cms.get(sh) || 0) + performance.now() - t); return r; };
    wrap('compileShader', () => { log.compiles += 1; });
    // what each program is: its variant's defines and its material's uniform names (the
    // game's own shaders read by those), to see which kinds cost the most programs
    const src = new WeakMap();
    const att = new WeakMap();
    const ss = P.shaderSource;
    P.shaderSource = function (sh, text) { src.set(sh, text); return ss.call(this, sh, text); };
    const as = P.attachShader;
    P.attachShader = function (pr, sh) { if (!att.has(pr)) att.set(pr, []); att.get(pr).push(sh); return as.call(this, pr, sh); };
    const what = (pr) => {
      const texts = (att.get(pr) || []).map((sh) => src.get(sh) || '');
      const all = texts.join('\n');
      const defs = [...new Set((all.match(/#define (USE_[A-Z0-9_]+|MODE_[A-Z0-9_]+|RENDER_[A-Z0-9_]+)/g) || []).map((d) => d.slice(8)))].sort();
      const m = all.match(/MaterialUniforms\s*{([^}]*)}/);
      const names = m ? (m[1].match(/\b([a-z_][a-z0-9_]*)\s*(\[[^\]]*\])?\s*;/gi) || []).map((x) => x.replace(/[;\s]|\[.*\]/g, '')).slice(0, 6).join(',') : '-';
      let h = 0;
      for (let i = 0; i < all.length; i++) h = (h * 31 + all.charCodeAt(i)) | 0;
      const ms = (att.get(pr) || []).reduce((a, sh) => a + (cms.get(sh) || 0), 0);
      // a default lit program as it reached the driver (this wrapper sits under the game's)
      const litDefault = all.includes('#define BASE_PASS') && !all.includes('#define USE_ADDITIVE_LIGHTING')
        && !all.includes('#define DISABLE_LIGHT_OMNI');
      return { defs: defs.join(' '), names, len: all.length, h, ms, litDefault, text: window.__dump ? all : undefined };
    };
    log.what = [];
    wrap('linkProgram', (t, dt) => { log.links.push([t, dt]); });
    const lp = P.linkProgram;
    P.linkProgram = function (pr) { log.what.push(what(pr)); return lp.call(this, pr); };
    const gpp = P.getProgramParameter;
    P.getProgramParameter = function (pr, p) { const t = performance.now(); const r = gpp.call(this, pr, p); const w = log.what[log.what.length - 1]; if (w) w.ms += performance.now() - t; return r; };
    wrap('getProgramParameter', (t, dt) => { if (log.links.length) log.links[log.links.length - 1][1] += dt; });
    wrap('getShaderParameter', () => {});
  });
  const marks = {};
  const t0 = Date.now();
  let done = false;
  page.on('console', async (m) => {
    const text = m.text();
    if (text.startsWith('[streets] warm-up begins')) marks.begin = await page.evaluate(() => performance.now());
    if (text.startsWith('[streets] warm-up done')) { marks.end = await page.evaluate(() => performance.now()); marks.done = text; }
    if (text.includes('=== END REPORT ===')) done = true;
    const qm = text.match(/^\[streets\] quality walk: to (\d)/);
    if (qm) (marks.qsteps = marks.qsteps || []).push([await page.evaluate(() => performance.now()), Number(qm[1])]);
    if (/SCRIPT ERROR|USER ERROR/.test(text)) console.log('  game: ' + text.split('\n')[0]);
  });
  await page.goto(`http://localhost:${port}/`);
  const limit = Date.now() + (seconds + 600) * 1000;
  while (!done && Date.now() < limit) {
    await page.waitForTimeout(2000);
    if (marks.end && Date.now() - t0 > 0 && !marks.waited) {
      marks.waited = Date.now();
    }
    if (marks.waited && Date.now() - marks.waited > seconds * 1000 + 15000 + (qwalk ? 7 * qwalk * 1000 : 0)) break;
  }
  marks.clicks = [];
  if (times && marks.end) {
    const vp = page.viewportSize();
    for (let k = 0; k < times; k += 1) {
      marks.clicks.push(await page.evaluate(() => performance.now()));
      await page.mouse.click((452 + 26) * vp.width / 640, (334 + 10) * vp.height / 360);
      await page.waitForTimeout(gap * 1000);
    }
  }
  const gl = await page.evaluate(() => window.__gl);
  if (process.env.DUMP) {
    fs.writeFileSync(process.env.DUMP, JSON.stringify(gl.links.map(([t], i) => ({ phase: (marks.begin === undefined || t < marks.begin) ? 'before' : (marks.end === undefined || t < marks.end ? 'warm-up' : 'after'), ...gl.what[i] }))));
    console.log('sources written to ' + process.env.DUMP);
  }
  const links = gl.links;
  const phase = (t) => (marks.begin === undefined || t < marks.begin) ? 'before' : (marks.end === undefined || t < marks.end ? 'warm-up' : 'after');
  const sum = { before: [0, 0], 'warm-up': [0, 0], after: [0, 0] };
  for (const [t, dt] of links) { sum[phase(t)][0] += 1; sum[phase(t)][1] += dt; }
  console.log(`programs linked: ${links.length} (shaders compiled ${gl.compiles}), ${Math.round(gl.ms)} ms in compile/link/status calls`);
  for (const k of ['before', 'warm-up', 'after']) console.log(`  ${k.padEnd(8)} ${String(sum[k][0]).padStart(4)} programs, ${Math.round(sum[k][1])} ms`);
  if (marks.done) console.log('  ' + marks.done);
  // by material (its uniform names) and by variant
  const by = {}, vars = {};
  links.forEach(([t], i) => {
    const w = gl.what[i] || { names: '?', defs: '' };
    const k = w.names || '-';
    by[k] = by[k] || [0, 0, new Set(), 0];
    by[k][0] += 1;
    by[k][3] += w.ms || 0;
    if (phase(t) === 'warm-up') by[k][1] += 1;
    by[k][2].add(w.h);
    vars[w.defs] = (vars[w.defs] || 0) + 1;
  });
  console.log('by material (its first uniforms): programs (in the warm-up), distinct sources, ms compiling them');
  Object.entries(by).sort((a, b) => b[1][3] - a[1][3]).slice(0, 40)
    .forEach(([k, v]) => console.log(`  ${String(v[0]).padStart(3)} (${String(v[1]).padStart(3)}) ${String(v[2].size).padStart(3)} ${String(Math.round(v[3])).padStart(6)} ms  ${k}`));
  console.log('by variant (defines):');
  Object.entries(vars).sort((a, b) => b[1] - a[1]).slice(0, 25).forEach(([k, v]) => console.log(`  ${String(v).padStart(3)}  ${k || '(none)'}`));
  const after = links.filter(([t]) => phase(t) === 'after').map(([t, dt]) => `${((t - marks.end) / 1000).toFixed(1)} s (${Math.round(dt)} ms)`);
  if (after.length) console.log('  after the warm-up, at: ' + after.slice(0, 30).join(', '));
  const names = ['evening', 'night', 'day'];
  marks.clicks.forEach((tc, k) => {
    const next = marks.clicks[k + 1] === undefined ? Infinity : marks.clicks[k + 1];
    const mine = links.map(([t], i) => [t, gl.what[i]]).filter(([t]) => t >= tc && t < next);
    console.log(`click ${k + 1} (to ${names[k % 3]}): ${mine.length} programs`);
    const byk = {};
    mine.forEach(([, w]) => { const key = `${(w && w.names) || '-'}  [${(w && w.defs) || ''}]`; byk[key] = (byk[key] || 0) + 1; });
    Object.entries(byk).sort((a, b) => b[1] - a[1]).forEach(([key, v]) => console.log(`  ${String(v).padStart(3)}  ${key}`));
  });
  (marks.qsteps || []).forEach(([tq, q], k) => {
    const next = marks.qsteps[k + 1] === undefined ? Infinity : marks.qsteps[k + 1][0];
    const mine = links.map(([t, dt], i) => [t, dt, gl.what[i]]).filter(([t]) => t >= tq && t < next);
    const ms = mine.reduce((a, [, dt]) => a + dt, 0);
    console.log(`quality step ${k + 1} (to ${q}): ${mine.length} programs, ${Math.round(ms)} ms`);
    const byk = {};
    mine.forEach(([, , w]) => { const key = `${(w && w.names) || '-'}  [${(w && w.defs) || ''}]`; byk[key] = (byk[key] || 0) + 1; });
    Object.entries(byk).sort((a, b) => b[1] - a[1]).slice(0, 12).forEach(([key, v]) => console.log(`  ${String(v).padStart(3)}  ${key}`));
  });
  if (qwalk) console.log(`quality steps seen: ${(marks.qsteps || []).length} of 6`);
  // The family "programs compiled that are never drawn": Godot compiles each material's
  // default lit program (omni, spot and area light code on) and never draws with it; the
  // game swaps those for a placeholder (LIGHT_STRIP_JS in streets.gd), which cut a cold load
  // ~10x on Windows browsers. A Godot upgrade or a changed define would let them back in
  // silently: none may reach the driver, and nothing may be drawn with a placeholder.
  const escaped = gl.what.filter((w) => w && w.litDefault).length;
  const ls = await page.evaluate(() => window.__lstrip || null);
  const okEsc = escaped === 0, okUsed = !!ls && ls.used === 0;
  console.log(`CHECK never-drawn lit programs compiled: ${escaped} (want 0) ${okEsc ? 'PASS' : 'FAIL'}`);
  console.log(`CHECK placeholders: ${ls ? ls.n : 'none -- LIGHT_STRIP_JS not on'}, drawn with: ${ls ? ls.used : '-'} (want 0) ${okUsed ? 'PASS' : 'FAIL'}`);
  if (!okEsc || !okUsed) process.exitCode = 1;
  console.log(`(${Math.round((Date.now() - t0) / 1000)} s of wall time)`);
  await browser.close();
  server.close();
})();
