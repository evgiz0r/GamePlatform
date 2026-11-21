#!/usr/bin/env python3
"""Split an exported web build's index.pck into a small main pack plus packs that rarely change.

Usage: tools/split_pck.py <export dir> <work dir>   (from the project root; tools/publish_web.sh runs it)

Why: a phone keeps the last build in its service worker's cache, but every publish used to
change index.pck -- the one ~40 MB file holding the code, every texture, model, sound and
city -- so a one-line code change sent the whole thing down again. After this split the main
index.pck holds the code, scenes and small files, and the big things that seldom change go in
packs of their own, each NAMED BY ITS CONTENT HASH (index.<group>.<hash>.pck): the same
content gives the same name, so the service worker can keep a pack across builds and a
publish costs only what really changed.

The groups (nothing here names a game):
  art    -- everything Godot imported (.godot/imported/*, and the *.import remaps that point
            at them) that is not a sound: textures, models
  sound  -- the imported sounds and music
  <name> -- each other file of DATA_MIN bytes or more (a baked city, say) on its own, unless
            it is code or a scene, or lives under a baked/ folder (made again every build)
  main   -- the rest, and res://packs.txt listing the packs, read at start by
            shell/autoload/packs.gd, which loads them before anything else is

This script only reads the export and lays the files out: tools/pack_write.gd then writes the
packs with Godot's own PCKPacker (so their format is always the engine's), using the
manifest.json left in <work dir>.
"""
import hashlib
import json
import os
import re
import struct
import sys

DATA_MIN = 256 * 1024
SOUND_EXT = ('.wav', '.ogg', '.mp3')
SOUND_IMPORTED = ('.sample', '.oggvorbisstr', '.mp3str')
CODE_EXT = ('.gd', '.gdc', '.gde', '.scn', '.tscn', '.res', '.tres', '.binary', '.cfg', '.bin', '.remap', '.import', '.uid')


def read_pck(path):
    d = open(path, 'rb').read()
    magic, fmt, major, minor, patch = struct.unpack_from('<4sIIII', d, 0)
    assert magic == b'GDPC', 'not a Godot pack'
    assert fmt >= 2, 'pack format %d: too old for this script' % fmt
    flags, file_base = struct.unpack_from('<IQ', d, 20)
    off = 32
    if fmt >= 3:
        dir_ofs, = struct.unpack_from('<Q', d, off)
        off = dir_ofs
    else:
        off += 16 * 4
    assert not (flags & 1), 'encrypted pack directory: cannot split'
    if flags & 2:   # PACK_REL_FILEBASE: file offsets count from the pack's start
        pass
    n, = struct.unpack_from('<I', d, off)
    off += 4
    files = []
    for _ in range(n):
        ln, = struct.unpack_from('<I', d, off)
        off += 4
        p = d[off:off + ln].rstrip(b'\0').decode('utf-8')
        off += ln
        ofs, size = struct.unpack_from('<QQ', d, off)
        off += 16 + 16   # offset, size, md5
        fflags, = struct.unpack_from('<I', d, off)
        off += 4
        assert not (fflags & 1), p + ' is encrypted: cannot split'
        files.append((p, d[file_base + ofs:file_base + ofs + size]))
    total = sum(len(b) for _, b in files)
    return files, total, (major, minor, patch)


def group_of(p, size):
    q = p[len('res://'):] if p.startswith('res://') else p
    if q.startswith('.godot/imported/'):
        return 'sound' if q.endswith(SOUND_IMPORTED) else 'art'
    if q.endswith('.import'):
        return 'sound' if q[:-len('.import')].lower().endswith(SOUND_EXT) else 'art'
    if q.startswith('.godot/') or q.lower().endswith(CODE_EXT) or '/baked/' in '/' + q:
        return 'main'
    if size >= DATA_MIN:
        stem = os.path.splitext(os.path.basename(q))[0].lower()
        return 'data_' + (re.sub(r'[^a-z0-9]+', '_', stem).strip('_') or 'file')
    return 'main'


def main():
    out, work = sys.argv[1], sys.argv[2]
    project = os.getcwd()   # (publish_web.sh runs it from the project's root)
    files, total, engine = read_pck(os.path.join(out, 'index.pck'))
    groups = {}
    for p, b in files:
        groups.setdefault(group_of(p, len(b)), []).append((p, b))
    # (two data files with the same stem in different folders simply share a pack)
    os.makedirs(work, exist_ok=True)
    packs = []
    for g in sorted(groups, key=lambda k: (k == 'main', k)):
        items = sorted(groups[g])
        h = hashlib.sha256()
        if g in ('art', 'sound'):
            # Named by what was imported, not by the import's output: Godot's import of a
            # model is not byte-for-byte repeatable (a fresh import on the publishing machine
            # wrote 47 of 700 files differently, the .scn of every glTF), so hashing the output
            # renamed the art pack on every publish and a phone fetched its 13 MB each time.
            # The engine version, every imported path, each .import remap as exported, and
            # the bytes of the source file it was imported from.
            h.update(('godot %d.%d.%d' % engine).encode('utf-8'))
            for p, b in items:
                h.update(p.encode('utf-8') + b'\0')
                if p.endswith('.import'):
                    h.update(b)
                    src = os.path.join(project, p[len('res://'):-len('.import')])
                    h.update(open(src, 'rb').read() if os.path.isfile(src) else b'(no source)')
        else:
            for p, b in items:
                h.update(p.encode('utf-8') + b'\0' + struct.pack('<Q', len(b)))
                h.update(b)
        name = 'index.pck' if g == 'main' else 'index.%s.%s.pck' % (g, h.hexdigest()[:12])
        entries = []
        for i, (p, b) in enumerate(items):
            src = os.path.join(work, g, '%05d' % i)
            os.makedirs(os.path.dirname(src), exist_ok=True)
            open(src, 'wb').write(b)
            entries.append([p, os.path.abspath(src)])
        packs.append({'group': g, 'name': name, 'files': entries, 'bytes': sum(len(b) for _, b in items)})
    names = [pk['name'] for pk in packs if pk['group'] != 'main']
    seen = set()
    for n in names:
        assert n not in seen, 'two packs named ' + n
        seen.add(n)
    listing = os.path.join(work, 'packs.txt')
    open(listing, 'w').write('\n'.join(names) + '\n')
    packs[-1]['files'].append(['res://packs.txt', os.path.abspath(listing)])
    json.dump({'out': os.path.abspath(out), 'packs': packs}, open(os.path.join(work, 'manifest.json'), 'w'))
    print('split index.pck (%.1f MB, %d files):' % (total / 1e6, len(files)))
    for pk in packs:
        print('  %-40s %6.2f MB  %4d files' % (pk['name'], pk['bytes'] / 1e6, len(pk['files'])))


if __name__ == '__main__':
    main()
