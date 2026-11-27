#!/usr/bin/env python3
"""Move a run of streets.gd's sections into a file of its own, changing nothing it does.

    python3 game/streets/data_tools/split_section.py START END module.gd Const _var [--dry]

START..END are streets.gd line numbers (END exclusive), normally from one "## ---- " header
to the next. The lines go to game/streets/<module.gd>, a RefCounted made once by the game
(`var _var := Const.new(self)`) that reaches back to it through a typed `g` (`var g: Streets`,
a preload of streets.gd: the cycle is fine in Godot 4, and keeping `g` typed keeps every `:=`
and every typo checked by the parser).

What is rewritten, token by token (strings and comments left alone):
  - in the moved lines, a name the rest of streets.gd (or GameMode / GameMode3D / Node)
    defines: a var or func becomes `g.name`; a const or class becomes `Streets.name`;
  - in the rest of streets.gd, a moved var or func becomes `_var.name`, a moved const or
    class `Const.name`;
  - in the other scripts of the game and its tests, `g.name` / `game.name` likewise.
A function's own parameters and locals are never touched. Everything the script cannot be
sure of (a `self`, a name in a string, a local with a member's name, a static func that
needs the game, a moved var whose initial value needs the game) is printed for a look by
hand. Then: tools/check_script.sh, and the fingerprint test (tests/fingerprint.gd) before and
after -- it must print the same.
"""
import re, sys, glob, os

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(GAME))

# GameMode / GameMode3D members and the Node API names the game calls on itself
INHERITED = set("""title play_area score lives finished start add_score set_lives lose_life win lose _finish
center random_edge_point in_play_area world_area MODELS_DIR view world cam sun env _mats _vc _res_scale
_proxies _shake _shake_decay _cam_base _build_view _fit_resolution look_from mat _tint _retint
ground_point screen_ray to_screen to_play from_play clamp_to_area model find_model aabb_of _acc_aabb fit
fitted_aabb add_box_collision track3d _sync shake3d hit3d
add_child remove_child get_tree get_viewport get_node get_node_or_null has_node get_children get_parent
is_inside_tree queue_free set_process set_physics_process set_process_input set_process_unhandled_input
get_window create_tween get_world_3d get_world_2d queue_redraw is_processing get_canvas_item
position rotation scale visible modulate global_position name owner find_child find_children
is_node_ready get_viewport_rect get_global_mouse_position get_local_mouse_position draw_line draw_rect
draw_circle draw_string draw_polyline draw_colored_polygon draw_set_transform draw_arc draw_texture_rect
draw_texture get_process_delta_time get_physics_process_delta_time process_mode z_index""".split())

NATIVE = set('Sky Environment Mesh Curve Image Shader Camera Light Timer Label Button Node Path Font Texture Material World Tween Viewport Skeleton Animation Gradient'.split())
TOP = re.compile(r'^(static func|func|static var|var|const|class|@onready var|@export var|signal|enum)\s+([A-Za-z_][A-Za-z0-9_]*)')
IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')


def code_spans(lines):
    """for every line, the list of (start, end) spans that are code (not string, not comment)"""
    out = []
    in_triple = None
    for l in lines:
        spans = []
        i = 0
        start = 0
        n = len(l)
        if in_triple:
            j = l.find(in_triple)
            if j < 0:
                out.append([])
                continue
            i = j + 3
            start = i
            in_triple = None
        while i < n:
            ch = l[i]
            if ch == '#':
                break
            if l.startswith('"""', i) or l.startswith("'''", i):
                q = l[i:i + 3]
                spans.append((start, i))
                j = l.find(q, i + 3)
                if j < 0:
                    in_triple = q
                    start = n
                    i = n
                    break
                i = j + 3
                start = i
                continue
            if ch in '"\'':
                spans.append((start, i))
                j = i + 1
                while j < n and l[j] != ch:
                    j += 2 if l[j] == '\\' else 1
                i = j + 1
                start = i
                continue
            i += 1
        if not in_triple:
            spans.append((start, i if i <= n else n))
        out.append([s for s in spans if s[1] > s[0]])
    return out


def defs_of(lines, spans):
    d = {}
    for i in range(len(lines)):
        if not spans[i] or spans[i][0][0] != 0:
            continue   # inside a string (a shader's lines)
        m = TOP.match(lines[i])
        if m:
            kind = m.group(1).split()[-1]
            d[m.group(2)] = ('const' if kind in ('const', 'class', 'enum') else kind, i)
    return d


def functions(lines, spans):
    """[(first, last_exclusive, set of locals)] for each top-level func"""
    res = []
    i = 0
    n = len(lines)
    while i < n:
        if re.match(r'^(static )?func ', lines[i]):
            j = i + 1
            while j < n and (lines[j].strip() == '' or lines[j].startswith(('\t', ' ', '#'))):
                j += 1
            # trailing blank/comment lines belong to nobody
            k = j
            while k > i + 1 and (lines[k - 1].strip() == '' or lines[k - 1].startswith('#')):
                k -= 1
            loc = set()
            head = ''
            for t in range(i, k):
                head += ''.join(lines[t][a:b] for a, b in spans[t])
                if re.search(r'\)\s*(->\s*[^:]+)?:\s*$', head):
                    break
            m = re.search(r'func\s+\w+\s*\((.*)\)', head, re.S)
            if m:
                for p in m.group(1).split(','):
                    pm = re.match(r'\s*([A-Za-z_]\w*)', p)
                    if pm:
                        loc.add(pm.group(1))
            for t in range(i + 1, k):
                code = ''.join(lines[t][a:b] for a, b in spans[t])
                for vm in re.finditer(r'\b(?:var|const)\s+([A-Za-z_]\w*)', code):
                    loc.add(vm.group(1))
                for fm in re.finditer(r'\bfor\s+([A-Za-z_]\w*)', code):
                    loc.add(fm.group(1))
                for lm in re.finditer(r'\bfunc\s*\(([^)]*)\)', code):
                    for p in lm.group(1).split(','):
                        pm = re.match(r'\s*([A-Za-z_]\w*)', p)
                        if pm:
                            loc.add(pm.group(1))
            res.append((i, k, loc))
            i = j
        else:
            i += 1
    return res


def rewrite(lines, spans, lo, hi, names, prefix_of, warn, label):
    """prefix every free use of `names` in lines[lo:hi]; prefix_of(name, line_index) -> prefix or None"""
    funcs = functions(lines, spans)
    loc_at = {}
    for a, b, loc in funcs:
        for t in range(a, b):
            loc_at[t] = loc
    for i in range(lo, hi):
        if not spans[i]:
            continue
        l = lines[i]
        loc = loc_at.get(i, set())
        decl = TOP.match(l) if spans[i][0][0] == 0 else None
        new = []
        last = 0
        for a, b in spans[i]:
            for m in IDENT.finditer(l, a, b):
                t = m.group(0)
                if t not in names:
                    continue
                s = m.start()
                k = s - 1
                while k >= 0 and l[k] in ' \t':
                    k -= 1
                if k >= 0 and l[k] == '.':
                    continue
                if s > 0 and l[s - 1] in '$%&^@':   # $Node, %Unique, &"name"... (not 'a % b')
                    continue
                if decl and decl.start(2) == s:
                    continue
                if t in loc:
                    if True:
                        warn.append("%s:%d local '%s' has a member's name -- left alone: %s" % (label, i + 1, t, l.strip()))
                    continue
                p = prefix_of(t, i)
                if p is None:
                    continue
                new.append(l[last:s])
                new.append(p + t)
                last = m.end()
        if new:
            new.append(l[last:])
            lines[i] = ''.join(new)
    return lines


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry' in sys.argv
    start, end, module, cname, vname = int(args[0]), int(args[1]), args[2], args[3], args[4]
    path = os.path.join(GAME, 'streets.gd')
    lines = open(path).read().split('\n')
    lo, hi = start - 1, end - 1
    spans = code_spans(lines)
    alld = defs_of(lines, spans)
    for k in sys.argv:
        if k.startswith('--keep='):
            keep = set(k[7:].split(','))
            break
    else:
        keep = set()
    if cname in alld or vname in alld or vname in INHERITED or cname in NATIVE:
        sys.exit("%s or %s is already a name in streets.gd: pick another" % (cname, vname))
    # --keep=a,b: vars of the section that belong to the whole game, and helpers the other
    # scripts call, stay in streets.gd (with the ## lines over them, where the section was)
    kept = []
    for n in sorted(keep, key=lambda n: alld[n][1]):
        i = alld[n][1]
        if not (lo <= i < hi) or not re.match(r'^(static )?(var|func) ', lines[i]):
            sys.exit("--keep %s: not a var or func of the section" % n)
        a = i
        while a > lo + 1 and lines[a - 1].startswith('##') and not lines[a - 1].startswith('## ----'):
            a -= 1
        z = i + 1
        if re.match(r'^(static )?func ', lines[i]):
            while z < hi and (lines[z].strip() == '' or lines[z].startswith(('\t', ' ', '#'))):
                z += 1
            while z > i + 1 and lines[z - 1].strip() == '':
                z -= 1
        kept += lines[a:z]
        del lines[a:z]
        hi -= z - a
        spans = code_spans(lines)
        alld = defs_of(lines, spans)
    moved = {n: v for n, v in alld.items() if lo <= v[1] < hi}
    outside = {n: v for n, v in alld.items() if n not in moved}
    for n in keep:
        outside[n] = ('func', -1)
    for n in keep:
        outside[n] = ('func', -1)
    warn = []

    # ---- the moved lines
    sec = lines[lo:hi]
    ssp = spans[lo:hi]
    # inner classes in the moved lines: their bodies only see consts and classes
    in_class = set()
    cur = None
    for i, l in enumerate(sec):
        if l.startswith('class '):
            cur = i
            continue
        if cur is not None:
            if l.strip() and not l.startswith(('\t', ' ', '#')):
                cur = None
            else:
                in_class.add(i)
    const_line = {i for i, l in enumerate(sec) if l.startswith('const ')}
    var_init = {i for i, l in enumerate(sec) if re.match(r'^(static )?var ', l)}
    static_fn = set()
    for a, b, _ in functions(sec, ssp):
        if sec[a].startswith('static '):
            static_fn.update(range(a, b))
    names = set(outside) | INHERITED
    # a local named g would hide the game: it becomes g_ (only in the function that has it)
    for a, b, loc in functions(sec, ssp):
        if 'Streets' in loc or ('g' in loc and 'g_' in loc):
            sys.exit("moved:%d a local named Streets, or g and g_: rename it first (%s)" % (start + a, sec[a].strip()))
        if 'g' in loc:
            for t in range(a, b):
                l = sec[t]
                for x, y in reversed(ssp[t]):
                    l = l[:x] + re.sub(r'(?<![\w.])g(?!\w)', 'g_', l[x:y]) + l[y:]
                sec[t] = l
            ssp[a:b] = code_spans(sec[a:b])
            warn.append("moved:%d its local g is g_ now: %s" % (start + a, sec[a].strip()))

    def pre_moved(t, i):
        kind = outside[t][0] if t in outside else 'func'
        if kind == 'const':
            return 'Streets.'
        if i in in_class or i in const_line or i in static_fn:
            warn.append("moved:%d '%s' (a %s of the game) from a class, const or static func: %s" % (start + i, t, kind, sec[i].strip()))
            return 'g.'
        if i in var_init:
            warn.append("moved:%d a var's initial value needs the game ('%s'): %s" % (start + i, t, sec[i].strip()))
        return 'g.'
    sec = rewrite(sec, ssp, 0, len(sec), names, pre_moved, warn, 'moved')
    for i, l in enumerate(sec):
        code = ''.join(l[a:b] for a, b in ssp[i])
        if re.search(r'\bself\b|\bsuper\b|@onready|\bawait\b', code):
            warn.append("moved:%d look at: %s" % (start + i, l.strip()))

    # ---- the rest of streets.gd
    def pre_rest(t, i):
        return cname + '.' if moved[t][0] == 'const' else vname + '.'
    rest = lines[:lo] + kept + lines[hi:]
    rsp = code_spans(rest)
    rest = rewrite(rest, rsp, 0, len(rest), set(moved), pre_rest, warn, 'streets')
    # strings anywhere naming a moved thing
    for i, l in enumerate(rest):
        for t in re.findall(r'["\']([A-Za-z_]\w*)["\']', l):
            if t in moved:
                warn.append("streets:%d '%s' in a string: %s" % (i + 1, t, l.strip()))

    # ---- the module
    head = sec[0]
    title = re.sub(r'^## ---- ', '', head).rstrip('- ').strip()
    body = sec[1:]
    while body and body[-1].strip() == '':
        body.pop()
    mod = ['extends RefCounted',
           '## ' + title[0].upper() + title[1:] + ' (moved out of streets.gd; `g` is the game).']
    k = 0
    while k < len(body) and body[k].startswith('##'):
        mod.append(body[k])
        k += 1
    mod += ['', 'const Streets := preload("res://game/streets/streets.gd")', '', 'var g: Streets', '',
            'func _init(game: Streets) -> void:', '\tg = game', '']
    mod += body[k:]
    mod.append('')

    # the hook left in streets.gd where the lines were
    hook = [head,
            '## In `%s` (`%s`, made once: `%s`).' % (module, cname, vname),
            'const %s := preload("res://game/streets/%s")' % (cname, module),
            'var %s := %s.new(self)' % (vname, cname), '']
    out = rest[:lo] + hook + rest[lo:]

    # ---- other scripts reaching in through g. / game.
    others = {}
    for f in sorted(glob.glob(os.path.join(GAME, '**', '*.gd'), recursive=True)) + \
            sorted(glob.glob(os.path.join(ROOT, 'lab', '**', '*.gd'), recursive=True)):
        if os.path.abspath(f) in (path, os.path.join(GAME, module)):
            continue
        src = open(f).read()
        def sub(m):
            t = m.group(2)
            if t not in moved:
                return m.group(0)
            return m.group(1) + '.' + (cname if moved[t][0] == 'const' else vname) + '.' + t
        new = re.sub(r'\b(g|game|_g|G)\.([A-Za-z_]\w*)\b', sub, src)
        # an earlier split's module reaching a const of the game: Streets.NAME
        new = re.sub(r'\bStreets\.([A-Za-z_]\w*)\b', lambda m: ('Streets.' + cname + '.' + m.group(1)) if m.group(1) in moved and moved[m.group(1)][0] == 'const' else m.group(0), new)
        if new != src:
            others[f] = new
        for t in moved:
            for m in re.finditer(r'["\']' + re.escape(t) + r'["\']', new):
                ln = new[:m.start()].count('\n')
                warn.append("%s:%d '%s' named in a string (a constant map? call()?): %s" % (os.path.relpath(f, ROOT), ln + 1, t, new.split('\n')[ln].strip()))
            for m in re.finditer(r'(?<![\w.])' + re.escape(t) + r'\b', new):
                ln = new[:m.start()].count('\n')
                warn.append("%s:%d bare '%s' (not through g.): %s" % (os.path.relpath(f, ROOT), ln + 1, t, new.split('\n')[ln].strip()))

    print("moved %d lines, %d names: %s" % (hi - lo, len(moved), ', '.join(sorted(moved))))
    print("other scripts changed: %s" % ', '.join(os.path.relpath(f, ROOT) for f in others))
    for w in warn:
        print("CHECK", w)
    if dry:
        return
    open(path, 'w').write('\n'.join(out))
    open(os.path.join(GAME, module), 'w').write('\n'.join(mod))
    for f, src in others.items():
        open(f, 'w').write(src)


main()
