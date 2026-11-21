#!/usr/bin/env python3
"""Landmarks: where the film puts a thing against where the replay has it, in metres.

A mark is a thing standing on the ground (a pole, a bollard, a bin, a column, a corner of a
wall, a person's feet) seen in one film frame: its foot's place in the frame. Through the
replay camera's exact pose at that moment (filmed_walk RECORD=1 prints a POSE a frame) the
foot is a ray, and the ray meets the ground: that is where the film says the thing stands,
*if the replay's camera stands where the film's did*. Set beside the thing's place in the
game, the difference is how far off it is. Several marks of one thing from frames a few
seconds apart agree when the thing is misplaced and disagree when the camera is (the camera's
own error shows as every thing in one frame off the same way: printed per frame).

  film_marks.py label <rec log> <game frames> <film frames> <t> <out.jpg> [r]
      the game's frame at t with every post the log lists (POST lines: bollards, poles,
      columns, trunks, bins) projected and numbered, beside the film's frame at t with a grid
      of tenths -- to name what to mark and read off where. r: only posts of that radius or
      under (default 0.6)
  film_marks.py solve <marks.csv> <rec log> [places.csv]
      the answer: every mark at once (a small bundle adjustment). Each thing gets one place;
      each marked frame's phone may turn, tip and stand a little off the replay's camera
      (held near it: 3 deg, 3 deg, 1 m), so a hand's tip does not read as a thing 20 m off.
      Prints how well it fits, where the film's phone stood against the replay's, and each
      thing's place against the game's (its own post, or the nearest). Mark each thing in
      two frames or more, a couple of seconds apart, from different places; `fixed post N`
      holds a thing where the game has it (an anchor).
  film_marks.py check <marks.csv> <rec log> [film frames] [out dir]
      every mark: the film's place on the ground, the game's, the difference (along the
      walk's view and across it), the bearing's error; per thing the median; per frame the
      mean (the camera's share). With film frames, out dir gets each marked frame with the
      film's foot (green) and the game's thing projected (red).

marks.csv: `thing, t, x, y` -- the thing (`post 1234`, or `at x z` for anything the log has
no post for: a corner from the city file), the film second, and the foot's place in the film's
frame as fractions (0 left / top, 1 right / bottom). Read them off the 1080p film (1080x1920
upright; extract with ffmpeg `trim=...,fps=2`), not the 406x720 copy: a tenth of a degree is
two of its pixels.

The film's frame is the phone's: 70 degrees up and down, 43.1 across (the replay's camera is set
the same: cam.fov 70, its middle 406 of 1280 columns). Within ~3 m a foot's height in the frame
is a good range; past ~15 m, a pixel is a metre, and only the bearing is worth reading:
the check prints the range it trusts.
Needs numpy (and PIL for the pictures).
"""
import csv
import math
import os
import sys

import numpy as np

FH = 720.0                                   # the replay's frame, rows
FW = 1280.0
CW = 406.0                                   # the phone's upright frame within it
F = (FH / 2) / math.tan(math.radians(35.0))  # focal length in those pixels


def read_log(path):
    poses = {}
    posts = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            p = line.split()
            if not p:
                continue
            if p[0] == "POSE":
                v = [float(x) for x in p[1:12]]
                poses[round(v[0], 1)] = (np.array(v[1:4]), np.array(v[4:7]), np.array(v[7:10]))
            elif p[0] == "POST":
                posts[int(p[1])] = (float(p[2]), float(p[3]), float(p[4]), float(p[5]))
    return poses, posts


def pose_at(poses, t):
    k = round(t, 1)
    if k in poses:
        return poses[k]
    ks = np.array(sorted(poses))
    return poses[float(ks[np.argmin(np.abs(ks - t))])]


def project(pose, p):
    """a world point to fractions of the phone's frame (x, y) and its depth"""
    o, f, u = pose
    r = np.cross(f, u)
    d = np.asarray(p) - o
    z = float(d @ f)
    if z <= 0.1:
        return None
    px = FW / 2 + F * float(d @ r) / z
    py = FH / 2 - F * float(d @ u) / z
    return ((px - (FW - CW) / 2) / CW, py / FH, z)


def ray_ground(pose, fx, fy, ground_y):
    """the film's foot at fractions (fx, fy) onto the plane y = ground_y"""
    o, f, u = pose
    r = np.cross(f, u)
    d = f + r * ((fx * CW - CW / 2) / F) - u * ((fy * FH - FH / 2) / F)
    if d[1] >= -1e-4:
        return None
    s = (ground_y - o[1]) / d[1]
    return o + d * s


EYE = 1.44   # the phone above the ground on a filmed walk (streets.gd _foot_camera: 1.64 - 0.2)


def thing_pos(thing, posts):
    p = thing.split()
    if p[0] == "post" and len(p) == 2 and p[1].isdigit():
        x, z, r, h = posts[int(p[1])]
        return np.array([x, h, z]), r
    if p[0] == "at":
        # at x z [ground y]: no ground given, the camera's height less 1.25 is used later
        return np.array([float(p[1]), float(p[3]) if len(p) > 3 else float("nan"), float(p[2])]), 0.0
    return None, 0.0   # a thing the game may not have: the film's place only, and what is nearest


def check(marks_path, log_path, film_dir=None, out=None):
    poses, posts = read_log(log_path)
    rows = []
    with open(marks_path, encoding="utf-8") as fh:
        for r in csv.reader(fh):
            if not r or r[0].strip().startswith("#"):
                continue
            rows.append((r[0].strip(), float(r[1]), float(r[2]), float(r[3]), (r[4].strip() if len(r) > 4 else "")))
    per_thing = {}
    per_frame = {}
    free = {}
    print("%-16s %6s  %-17s %-17s %6s %6s %6s %7s" % ("thing", "t", "film (x,z)", "game (x,z)", "along", "across", "range", "bearing"))
    for thing, t, fx, fy, note in rows:
        pose = pose_at(poses, t)
        gp, rad = thing_pos(thing, posts)
        o, f, u = pose
        if gp is None:   # the film's thing alone: where it stands, the game's nearest post
            hit = ray_ground(pose, fx, fy, o[1] - EYE)
            if hit is None:
                print("%-16s %6.1f  foot above the horizon" % (thing, t))
                continue
            free.setdefault(thing, []).append((hit[0], hit[2], float(np.hypot(hit[0] - o[0], hit[2] - o[2]))))
            print("%-16s %6.1f  (%7.1f,%7.1f) %s %4.1f m away %s" % (thing, t, hit[0], hit[2], " " * 17,
                  free[thing][-1][2], note))
            if film_dir and out:
                picture(film_dir, t, fx, fy, None, thing, out)
            continue
        if math.isnan(gp[1]):
            gp[1] = o[1] - EYE
        hit = ray_ground(pose, fx, fy, gp[1])
        proj = project(pose, gp)
        fwd = np.array([f[0], f[2]])
        fwd /= np.linalg.norm(fwd)
        side = np.array([-fwd[1], fwd[0]])   # to the right on the map (x right, z down the screen)
        # the film's bearing to the thing, and the game's, from the camera (degrees, + right)
        b_film = math.degrees(math.atan((fx * CW - CW / 2) / F))
        b_game = math.degrees(math.atan((proj[0] * CW - CW / 2) / F)) if proj else float("nan")
        if hit is None:
            print("%-16s %6.1f  foot above the horizon: bearing only, film %+.1f game %+.1f deg" % (thing, t, b_film, b_game))
            per_thing.setdefault(thing, []).append((float("nan"), float("nan"), b_game - b_film, float("nan")))
            continue
        d = np.array([hit[0] - gp[0], hit[2] - gp[2]])   # film's place less the game's
        rng = float(np.hypot(hit[0] - o[0], hit[2] - o[2]))
        along = float(d @ fwd)
        across = float(d @ side)
        print("%-16s %6.1f  (%7.1f,%7.1f) (%7.1f,%7.1f) %+6.1f %+6.1f %6.1f %+6.1f %s" % (thing, t, hit[0], hit[2], gp[0], gp[2],
              along, across, rng, b_game - b_film, note))
        per_thing.setdefault(thing, []).append((d[0], d[1], b_game - b_film, rng))
        per_frame.setdefault(t, []).append(b_game - b_film)
        if film_dir and out:
            picture(film_dir, t, fx, fy, proj, thing, out)
    print("\nper thing (median; move the game's thing by dx,dz to put it where the film has it):")
    for thing, v in per_thing.items():
        a = np.array(v)
        ok = a[~np.isnan(a[:, 0])]
        rng = np.nanmedian(a[:, 3]) if len(ok) else float("nan")
        trust = "range and bearing" if rng < 12 else "bearing only (far: a metre is a pixel or two up and down)"
        if len(ok):
            print("  %-16s %d marks  dx %+5.1f dz %+5.1f m (%.1f m), bearing off %+5.1f deg, %4.1f m away -- %s"
                  % (thing, len(v), np.median(ok[:, 0]), np.median(ok[:, 1]),
                     math.hypot(np.median(ok[:, 0]), np.median(ok[:, 1])), np.median(a[:, 2]), rng, trust))
        else:
            print("  %-16s %d marks  bearing off %+5.1f deg" % (thing, len(v), np.median(a[:, 2])))
    if free:
        print("\nthe film's things, one frame at a time (read solve's places, not these: a foot's height in one\n"
              "frame is a range only if the phone was tipped as the replay's, and past ~5 m it never quite is)")
    print("\nper frame (the mean bearing error of its marks: the camera's facing, if they agree):")
    for t in sorted(per_frame):
        b = per_frame[t]
        print("  %5.1f s: %+5.1f deg over %d marks (spread %.1f)" % (t, np.mean(b), len(b), (max(b) - min(b)) if len(b) > 1 else 0))


def rot(axis, a):
    axis = axis / np.linalg.norm(axis)
    K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + math.sin(a) * K + (1 - math.cos(a)) * K @ K


def solve(marks_path, log_path, sigma_px=6.0, turn_deg=3.0, tip_deg=3.0, step_m=1.0, out=None):
    """every mark at once: each thing's one place, and each marked frame's phone -- its facing,
    tip and place on the ground -- a little off the replay's camera, pulled back toward it
    (sigma: turn_deg, tip_deg, step_m) so the marks decide only what they can. Marks are
    weighed at sigma_px pixels of the 720-row frame. Things named `post N` / `at x z` are
    compared with the game's; `fixed post N` / `fixed at x z` are held where the game has them
    (anchors: a corner from the city file, a pole the map has right)."""
    from scipy.optimize import least_squares
    poses, posts = read_log(log_path)
    obs = []
    with open(marks_path, encoding="utf-8") as fh:
        for r in csv.reader(fh):
            if r and not r[0].strip().startswith("#"):
                obs.append((r[0].strip(), float(r[1]), float(r[2]), float(r[3])))
    frames = sorted({o[1] for o in obs})
    names = []
    for o in obs:
        if o[0] not in names:
            names.append(o[0])
    fixed = {}
    game = {}
    for n in names:
        key = n[6:] if n.startswith("fixed ") else n
        gp, _ = thing_pos(key, posts)
        if gp is not None:
            game[n] = gp
            if n.startswith("fixed "):
                fixed[n] = gp
    free_names = [n for n in names if n not in fixed]
    fi = {t: k for k, t in enumerate(frames)}
    ti = {n: k for k, n in enumerate(free_names)}
    base = {t: pose_at(poses, t) for t in frames}
    ground = {}
    for n in names:   # each thing's ground: the eyes of the frames that see it, less the eye's height
        ys = [base[o[1]][0][1] - EYE for o in obs if o[0] == n]
        ground[n] = float(np.mean(ys)) if not (n in game and not math.isnan(game[n][1])) else float(game[n][1])
    # a start for each free thing: the nearest-range mark's ground hit through the replay's camera
    x0 = np.zeros(4 * len(frames) + 2 * len(free_names))
    for n in free_names:
        best = None
        for o in obs:
            if o[0] != n:
                continue
            h = ray_ground(base[o[1]], o[2], o[3], ground[n])
            if h is not None:
                rng = float(np.hypot(h[0] - base[o[1]][0][0], h[2] - base[o[1]][0][2]))
                if rng < 40 and (best is None or rng < best[0]):
                    best = (rng, h)
        if best is None:
            o = next(o for o in obs if o[0] == n)
            pz = base[o[1]]
            best = (10, pz[0] + pz[1] * 10)
        x0[4 * len(frames) + 2 * ti[n]: 4 * len(frames) + 2 * ti[n] + 2] = (best[1][0], best[1][2])

    def pose_of(p, t):
        o, f, u = base[t]
        k = 4 * fi[t]
        dyaw, dtip, da, ds = p[k:k + 4]
        r = np.cross(f, u)
        fwd = np.array([f[0], 0, f[2]])
        fwd /= np.linalg.norm(fwd)
        side = np.array([-fwd[2], 0, fwd[0]])
        R = rot(np.array([0, 1.0, 0]), -dyaw) @ rot(r, -dtip)
        return (o + fwd * da + side * ds, R @ f, R @ u)

    def where(p, n):
        if n in fixed:
            return fixed[n]
        k = 4 * len(frames) + 2 * ti[n]
        return np.array([p[k], ground[n], p[k + 1]])

    def resid(p):
        res = []
        for n, t, fx, fy in obs:
            pr = project(pose_of(p, t), where(p, n))
            if pr is None:
                res += [50.0, 50.0]
            else:
                res += [(pr[0] - fx) * CW / sigma_px, (pr[1] - fy) * FH / sigma_px]
        for t in frames:
            k = 4 * fi[t]
            res += [math.degrees(p[k]) / turn_deg, math.degrees(p[k + 1]) / tip_deg, p[k + 2] / step_m, p[k + 3] / step_m]
        return np.array(res)

    sol = least_squares(resid, x0, loss="soft_l1", f_scale=2.0)
    p = sol.x
    r = resid(p)[: 2 * len(obs)] * sigma_px
    print("%d marks of %d things over %d frames; fit %.1f px rms (of the 720-row frame), worst %.1f"
          % (len(obs), len(names), len(frames), float(np.sqrt(np.mean(r ** 2))), float(np.max(np.abs(r)))))
    # how sure: the places' spread from the Jacobian (a rough 1-sigma, in metres)
    J = sol.jac
    try:
        cov = np.linalg.pinv(J.T @ J)
    except np.linalg.LinAlgError:
        cov = None
    print("\nthe film's phone against the replay's camera (+ along: further on; + across: to the right):")
    for t in frames:
        k = 4 * fi[t]
        print("  %5.1f s: turned %+5.1f deg, tipped %+5.1f deg, stood %+5.2f m along %+5.2f m across"
              % (t, math.degrees(p[k]), math.degrees(p[k + 1]), p[k + 2], p[k + 3]))
    print("\nthe things (where the film has them; the game's own, or its nearest post):")
    for n in names:
        w = where(p, n)
        sd = ""
        if n in ti and cov is not None:
            k = 4 * len(frames) + 2 * ti[n]
            sd = " +-%.1f m" % math.sqrt(max(0.0, cov[k, k] + cov[k + 1, k + 1]))
        seen = [o for o in obs if o[0] == n]
        mres = max(abs(float(v)) for i, o in enumerate(obs) if o[0] == n for v in r[2 * i: 2 * i + 2])
        line = "  %-20s (%7.1f, %7.1f)%s  %d marks, worst %.0f px" % (n, w[0], w[2], sd, len(seen), mres)
        if n in fixed:
            line += "  (held)"
        elif n in game:
            g = game[n]
            line += "  -- the game's at (%.1f, %.1f): move it %+.1f, %+.1f (%.1f m)" % (g[0], g[2], w[0] - g[0], w[2] - g[2],
                                                                                        math.hypot(w[0] - g[0], w[2] - g[2]))
        else:
            near = sorted((math.hypot(px - w[0], pz - w[2]), i, rr) for i, (px, pz, rr, h) in posts.items())[:2]
            near = [q for q in near if q[0] < 4.0]
            line += "  -- nearest: " + (", ".join("post %d (r %.2f) %.1f m" % (i, rr, d) for d, i, rr in near) or "no post within 4 m")
        print(line)
    if out:
        with open(out, "w", newline="") as fh:
            w_ = csv.writer(fh)
            w_.writerow(["thing", "x", "z"])
            for n in names:
                q = where(p, n)
                w_.writerow([n, "%.2f" % q[0], "%.2f" % q[2]])


def film_frame(film_dir, t):
    """the film's frame at t from a folder of h0000.jpg at 2 a second (1080p) or f00000.jpg at 10"""
    for name in ("h%04d.jpg" % round(t * 2), "f%05d.jpg" % round(t * 10)):
        p = os.path.join(film_dir, name)
        if os.path.exists(p):
            return p
    return None


def picture(film_dir, t, fx, fy, proj, thing, out):
    from PIL import Image, ImageDraw
    os.makedirs(out, exist_ok=True)
    path = film_frame(film_dir, t)
    if not path:
        return
    name = os.path.join(out, "mark_%05.1f.jpg" % t)
    im = Image.open(name if os.path.exists(name) else path).convert("RGB")
    if im.width > 600:
        im = im.resize((540, 960))
    d = ImageDraw.Draw(im)
    W, H = im.size
    d.ellipse([fx * W - 7, fy * H - 7, fx * W + 7, fy * H + 7], outline=(0, 255, 0), width=3)
    d.text((fx * W + 9, fy * H - 6), thing, fill=(0, 255, 0))
    if proj:
        x, y = proj[0] * W, proj[1] * H
        d.rectangle([x - 6, y - 6, x + 6, y + 6], outline=(255, 40, 40), width=3)
        d.line([fx * W, fy * H, x, y], fill=(255, 200, 0), width=1)
    im.save(name, quality=90)


def label(log_path, game_dir, film_dir, t, out, rmax=0.6):
    from PIL import Image, ImageDraw
    poses, posts = read_log(log_path)
    pose = pose_at(poses, t)
    g = Image.open(os.path.join(game_dir, "f%05d.jpg" % round(t * 10))).convert("RGB")
    x0 = (g.width - CW) / 2
    g = g.crop((x0, 0, x0 + CW, FH)).resize((540, 960))
    d = ImageDraw.Draw(g)
    for i, (x, z, r, h) in posts.items():
        if r > rmax:
            continue
        p = project(pose, (x, h, z))
        if not p or not (0 <= p[0] <= 1 and 0 <= p[1] <= 1.2) or p[2] > 60:
            continue
        X, Y = p[0] * 540, min(p[1], 1.0) * 960
        d.line([X, Y - 8, X, Y + 8], fill=(255, 60, 60), width=2)
        d.text((X + 3, Y - 12), "%d %.0fm" % (i, p[2]), fill=(255, 255, 0))
    path = film_frame(film_dir, t)
    f = Image.open(path).convert("RGB").resize((540, 960))
    df = ImageDraw.Draw(f)
    for k in range(1, 20):
        c = (255, 255, 255) if k % 2 == 0 else (150, 150, 150)
        df.line([k * 27, 0, k * 27, 960], fill=c, width=1)
        df.line([0, k * 48, 540, k * 48], fill=c, width=1)
        if k % 2 == 0:
            df.text((k * 27 + 2, 2), "%.1f" % (k / 20), fill=(255, 255, 0))
            df.text((2, k * 48 + 2), "%.1f" % (k / 20), fill=(255, 255, 0))
    im = Image.new("RGB", (1090, 980), (0, 0, 0))
    im.paste(f, (0, 20))
    im.paste(g, (550, 20))
    ImageDraw.Draw(im).text((4, 3), "%.1f s   film (grid: twentieths)  |  game, posts numbered with their distance" % t, fill=(255, 255, 255))
    im.save(out, quality=88)


if __name__ == "__main__":
    a = sys.argv
    if len(a) >= 7 and a[1] == "label":
        label(a[2], a[3], a[4], float(a[5]), a[6], float(a[7]) if len(a) > 7 else 0.6)
    elif len(a) >= 4 and a[1] == "solve":
        solve(a[2], a[3], out=a[4] if len(a) > 4 else None)
    elif len(a) >= 4 and a[1] == "check":
        check(a[2], a[3], a[4] if len(a) > 4 else None, a[5] if len(a) > 5 else None)
    else:
        print(__doc__)
        sys.exit(2)
