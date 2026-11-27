extends RefCounted
## The browser's shader compiling, counted (web only) (moved out of streets.gd; `g` is the game).
## A browser compiles a shader program the first time something is drawn with it (the
## warm-up's steps) and may keep what it compiled for the next visit (its program cache), when
## the same calls come back at once. Timed from the page itself, a phone's load line tells which
## it was: 200 programs in 50 s is compiling, 200 in 0.3 s the cache. The calls are wrapped on
## WebGL2's prototype, so the engine's context (made long before) goes through them too.

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const GL_COUNT_JS := """(() => {
	if (window.__glc || typeof WebGL2RenderingContext === 'undefined') return;
	const c = window.__glc = { n: 0, ms: 0 };
	const P = WebGL2RenderingContext.prototype;
	for (const name of ['compileShader', 'linkProgram', 'getShaderParameter', 'getProgramParameter']) {
		const f = P[name];
		P[name] = function (...a) {
			const t = performance.now();
			const r = f.apply(this, a);
			c.ms += performance.now() - t;
			if (name === 'linkProgram') c.n += 1;
			return r;
		};
	}
})()"""
## ---- the lit shaders Godot compiles and never draws with (web only) ---------------------
## When a material's shader is set up, Godot's Compatibility renderer compiles its "default"
## specialization of every variant at once (shader_gles3.cpp `_initialize_version`,
## `specialization_default_mask`): for the lit pass, plain and instanced, with the omni, spot
## and AREA light code all switched on. Draws never use it -- the base pass switches each of
## those off when no such light touches the instance (rasterizer_scene_gles3.cpp), and this
## game has only the sun. But Chrome/Edge on Windows hand every program to Direct3D's compiler,
## and those two cost ~2.4-7.7 s each: 44 of them were ~85% of a cold load (user's PC, 22 Nov
## 2026: Givatayim's graphics 63 s; area lights alone 2.45 -> 0.47 s a program, omni + spot +
## area 0.16 s). First the three were defined off in those sources (graphics 63 -> 22 s); even
## so the 42 never-drawn programs were 7.9 s of the 21 s left. Now they are swapped for a
## placeholder -- the source's own `#version` line and an empty main -- which costs nothing to
## compile. Picked out exactly: the base pass, not additive, no DISABLE_LIGHT_OMNI of their
## own (every draw of the base pass has it here: no omni light). Godot still links them, finds
## no uniforms in them (locations -1, which it skips) and never draws with them. If one ever
## IS drawn, `used` counts it and the console says so -- that draw would come out empty;
## `tests/web_shaders.js` / the load line show it (`window.__lstrip.used`).
## Since 22 Nov 2026 the page itself installs the same thing before the engine starts
## (tools/publish_web.sh, for every game: the engine's own default material at start was 2.8 s
## more), and this one finds `window.__lstrip` and does nothing -- it stays for a web export
## without that patch. And it is safe with any lights: a draw's base pass always sets
## DISABLE_LIGHTMAP (or a lightmap's own switch), so no draw uses the default specialization.
## `_no_local_lights` still warns if an omni, spot or area light appears (`used` says more).
const LIGHT_STRIP_JS := """(() => {
	if (window.__lstrip || typeof WebGL2RenderingContext === 'undefined') return;
	const c = window.__lstrip = { n: 0, used: 0 };
	const P = WebGL2RenderingContext.prototype;
	const types = new WeakMap(), fake = new WeakSet(), fakeProg = new WeakSet();
	const cs = P.createShader, ss = P.shaderSource, as = P.attachShader, up = P.useProgram;
	P.createShader = function (t) { const s = cs.call(this, t); if (s) types.set(s, t); return s; };
	P.shaderSource = function (s, src) {
		if (typeof src === 'string' && src.indexOf('#define BASE_PASS') >= 0
				&& src.indexOf('#define USE_ADDITIVE_LIGHTING') < 0 && src.indexOf('#define DISABLE_LIGHT_OMNI') < 0) {
			const v = src.slice(0, src.indexOf('\\n'));
			src = types.get(s) === this.VERTEX_SHADER
				? v + '\\nvoid main() { gl_Position = vec4(0.0); }\\n'
				: v + '\\nprecision mediump float;\\nout vec4 frag_color;\\nvoid main() { frag_color = vec4(1.0, 0.0, 1.0, 1.0); }\\n';
			fake.add(s);
			if (types.get(s) !== this.VERTEX_SHADER) c.n += 1;   // programs, not halves
		}
		return ss.call(this, s, src);
	};
	P.attachShader = function (p, s) { if (fake.has(s)) fakeProg.add(p); return as.call(this, p, s); };
	let cur = null;
	P.useProgram = function (p) { cur = p; return up.call(this, p); };
	for (const name of ['drawArrays', 'drawElements', 'drawArraysInstanced', 'drawElementsInstanced', 'drawRangeElements']) {
		const d = P[name];
		P[name] = function (...a) {
			if (cur && fakeProg.has(cur)) {
				if (c.used++ === 0) console.warn('[streets] LIGHT_STRIP_JS: a placeholder program was drawn with');
			}
			return d.apply(this, a);
		};
	}
})()"""

## warn if a light the strip above assumes away is in the scene
func _no_local_lights() -> void:
	for n in g.get_tree().root.find_children("*", "Light3D", true, false):
		if not (n is DirectionalLight3D):
			push_warning("[streets] %s is a %s: LIGHT_STRIP_JS assumes the game has none" % [n.name, n.get_class()])
			return


static func _gl_count_on() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(LIGHT_STRIP_JS, true)
		JavaScriptBridge.eval(GL_COUNT_JS, true)

## (programs linked, ms spent in the compile and link calls) so far; x -1 where not counted
static func _gl_count() -> Vector2:
	if not OS.has_feature("web"):
		return Vector2(-1, 0)
	var v = JavaScriptBridge.eval("window.__glc ? window.__glc.n + ',' + Math.round(window.__glc.ms) : ''", true)
	var t := str(v) if v != null else ""
	if t == "":
		return Vector2(-1, 0)
	return Vector2(float(t.get_slice(",", 0)), float(t.get_slice(",", 1)))
