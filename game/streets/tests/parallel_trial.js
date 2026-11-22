// The parallel-compile trial (22 Nov 2026, PERF.md "Parallel compiling, tried"): paste into
// a web build's page within ~0.2 s of opening it (the desktop app's browser pane: navigate,
// then javascript at once), before the engine links anything.
//  - No list stored yet (IndexedDB 'ptrial'): it only watches. Load a city, drive a while,
//    then run `window.__pt.recs` -> store with the snippet at the bottom.
//  - A list stored: on the first program the engine links (that is its real context --
//    the loader first makes a throwaway one to test WebGL, and a list linked there missed
//    every time), every program on the list is linked at once with
//    KHR_parallel_shader_compile, no status asked; when the engine then links the same
//    sources, it is handed the ready program (`red`: every call that takes a program goes
//    to it). window.__pt.hits / misses say how it went.
(() => {
  if (window.__pt) return 'already';
  const T = window.__pt = { hits: 0, misses: 0, pre: new Map(), preN: 0, preMs: 0, gl: null, recs: null, rec: [] };
  const P = WebGL2RenderingContext.prototype;
  const o = {};
  for (const k of Object.getOwnPropertyNames(P)) { try { if (typeof P[k] === 'function') o[k] = P[k]; } catch (e) {} }
  const typ = new WeakMap(), src = new WeakMap(), att = new WeakMap(), red = new WeakMap();
  const key = (shs) => shs.map(([t, s]) => t + '|' + s).join('\n@@\n');
  const prelink = (gl, recs) => {
    const t0 = performance.now();
    T.ext = !!gl.getExtension('KHR_parallel_shader_compile');
    for (const shs of recs) {
      const k = key(shs);
      if (T.pre.has(k)) continue;
      const p = o.createProgram.call(gl);
      for (const [t, s] of shs) { const sh = o.createShader.call(gl, t); o.shaderSource.call(gl, sh, s); o.compileShader.call(gl, sh); o.attachShader.call(gl, p, sh); }
      o.linkProgram.call(gl, p);
      T.pre.set(k, { gl, prog: p });
      T.preN++;
    }
    T.preMs = performance.now() - t0;
  };
  P.createShader = function (t) { const s = o.createShader.call(this, t); if (s) typ.set(s, t); return s; };
  P.shaderSource = function (s, t) { src.set(s, t); return o.shaderSource.call(this, s, t); };
  P.attachShader = function (p, s) { if (!att.has(p)) att.set(p, []); att.get(p).push(s); return o.attachShader.call(this, p, s); };
  P.linkProgram = function (p) {
    if (!T.gl && T.recs) { T.gl = this; prelink(this, T.recs); }
    const shs = (att.get(p) || []).map((s) => [typ.get(s), src.get(s) || '']);
    T.rec.push(shs);
    const q = T.pre.get(key(shs));
    if (q && q.gl === this) { red.set(p, q.prog); T.hits++; T.pre.delete(key(shs)); return; }
    T.misses++;
    return o.linkProgram.call(this, p);
  };
  for (const name of ['useProgram', 'getProgramParameter', 'getProgramInfoLog', 'getUniformLocation', 'getAttribLocation',
      'getUniformBlockIndex', 'uniformBlockBinding', 'getActiveUniform', 'getActiveAttrib', 'getActiveUniformBlockName',
      'getActiveUniformBlockParameter', 'getActiveUniforms', 'getUniformIndices', 'getUniform', 'getFragDataLocation',
      'getTransformFeedbackVarying', 'validateProgram', 'deleteProgram', 'detachShader', 'getAttachedShaders', 'isProgram',
      'bindAttribLocation', 'transformFeedbackVaryings']) {
    if (!o[name]) continue;
    const f = P[name];
    P[name] = function (p, ...a) { return f.call(this, (p && red.has(p)) ? red.get(p) : p, ...a); };
  }
  const r = indexedDB.open('ptrial', 1);
  r.onupgradeneeded = () => r.result.createObjectStore('m');
  r.onsuccess = () => { const g = r.result.transaction('m').objectStore('m').get('recs'); g.onsuccess = () => { T.recs = g.result || null; }; };
  return 'trial on';
})()
// store what this load linked, for the next:
// await new Promise((ok) => { const r = indexedDB.open('ptrial', 1); r.onupgradeneeded = () => r.result.createObjectStore('m');
//   r.onsuccess = () => { const tx = r.result.transaction('m', 'readwrite'); tx.objectStore('m').put(window.__pt.rec, 'recs'); tx.oncomplete = ok; }; })
