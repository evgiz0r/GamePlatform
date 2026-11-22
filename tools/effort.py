#!/usr/bin/env python3
"""How long each change took: agent, runs and you -- not the hours in between.

Reads the Claude Code session transcripts on this machine (~/.claude/projects/*/*.jsonl) and
this repo's history, finds each commit at the moment a session made it (a `git commit` the
session ran, matched by time and subject), and splits that session's time since its previous
commit (or its start) into:

  agent   the model thinking and writing (from a result or your message to its next step)
  runs    commands it waited on: tests, the engine, git (a tool call to its result), and the
          waits for a background run's notice
  you     from the end of its reply to your next message -- but a gap over AWAY_MIN (default
          10) minutes counts as away: none of it, not even the first ten
  away    what was dropped, for the record

Each gap is capped (agent and tool steps at 15 min, background waits at 30): past that the
machine slept or the session sat, and the rest counts as away too. Subagents' own records are
left out (their time is inside the main session's wait for them). Sessions running side by
side each count in full: the totals are session-minutes, not hours of anyone's day.

What a row cannot know: a commit holding several requests' work gets all of them (the time is
cut at commits, not at requests); talk between changes goes to the next commit; work from
another machine or the web is not in these transcripts.

--detail splits those minutes further: the agent's into thinking and writing (as the
transcript measured them) and waiting on the model -- before each step, the request going out
and the model reading the conversation before its first word: 2-4.5 s a step, thousands of
steps, a third of the agent's time (Nov 2026) -- and the runs' by what ran: the engine
(Godot, a playtest, a check), git, other shell, files, background runs waited on. A tool call
that waited on the person (a permission they clicked, a question) counts as theirs.

Writes one table per game, game/<name>/EFFORT.md (commits that touched that game's folder;
none for a game since deleted), and EFFORT.md at the root for the rest. Rows already in a table are kept as they are: Claude
Code deletes transcripts after a while (30 days by default), so run this now and then and the
history stays. Nothing from the transcripts goes in but times: commit subjects come from git.

  python tools/effort.py                  # every commit found, tables updated
  python tools/effort.py --since 2026-11-21 --print    # print, write nothing
  python tools/effort.py --last 8 --print
  python tools/effort.py --since 2026-11-22 --detail  # what the agent and run minutes were
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import subprocess
import sys

AGENT_CAP = 15 * 60
BG_CAP = 30 * 60


def ts(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def load_session(path):
    """the main thread's records, in time order, deduplicated"""
    seen = set()
    ev = []
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") not in ("user", "assistant") or d.get("isSidechain") or "timestamp" not in d:
            continue
        u = d.get("uuid")
        if u in seen:
            continue
        seen.add(u)
        ev.append(d)
    ev.sort(key=lambda d: d["timestamp"])
    return ev


def kind(d):
    """human / notice / result / tool / text / other"""
    m = d.get("message") or {}
    c = m.get("content")
    if d["type"] == "user":
        if isinstance(c, str):
            o = d.get("origin") or {}
            if isinstance(o, dict) and o.get("kind") == "human":
                return "human"
            if isinstance(o, dict) and o.get("kind") == "task-notification":
                return "notice"
            return "other"
        if isinstance(c, list) and any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c):
            return "result"
        return "other"
    if isinstance(c, list) and any(isinstance(x, dict) and x.get("type") == "tool_use" for x in c):
        return "tool"
    return "text"


def commit_calls(ev):
    """(time, command text) of each git commit the session ran"""
    out = []
    for d in ev:
        if d["type"] != "assistant":
            continue
        for x in (d.get("message") or {}).get("content") or []:
            if isinstance(x, dict) and x.get("type") == "tool_use":
                cmd = str((x.get("input") or {}).get("command", ""))
                if "git commit" in cmd or "commit-tree" in cmd:
                    out.append((ts(d["timestamp"]), cmd))
    return out


ENGINE = re.compile(r"GODOT|godot|playtest\.sh|check_script|shots\.sh|menu_shot|publish_web")


def tool_kind(d):
    """what a tool call ran: engine (Godot, a playtest, a check), git, shell, files, subagent, other"""
    for x in (d.get("message") or {}).get("content") or []:
        if not (isinstance(x, dict) and x.get("type") == "tool_use"):
            continue
        name = x.get("name", "")
        inp = x.get("input") or {}
        if name in ("Bash", "PowerShell"):
            cmd = str(inp.get("command", ""))
            if ENGINE.search(cmd):
                return "engine"
            if re.match(r"\s*(cd [^;&]*(&&|;)\s*)?git ", cmd) or " git push" in cmd or "git merge" in cmd:
                return "git"
            return "shell"
        if name in ("Read", "Edit", "Write", "Grep", "Glob", "NotebookEdit"):
            return "files"
        if name == "Agent":
            return "subagent"
        return "other tools"
    return "other tools"


def background(ev):
    """task id -> what it ran (tool_kind of the call that started it in the background)"""
    calls = {}
    for d in ev:
        if d["type"] == "assistant":
            for x in (d.get("message") or {}).get("content") or []:
                if isinstance(x, dict) and x.get("type") == "tool_use" and (x.get("input") or {}).get("run_in_background"):
                    calls[x.get("id")] = tool_kind(d)
    out = {}
    for d in ev:
        if d["type"] != "user":
            continue
        for x in (d.get("message") or {}).get("content") or []:
            if isinstance(x, dict) and x.get("type") == "tool_result" and x.get("tool_use_id") in calls:
                m = re.search(r"with ID: (\w+)", json.dumps(x.get("content")))
                if m:
                    out[m.group(1)] = calls[x["tool_use_id"]]
    return out


def split(ev, t0, t1, away_s, bg=None):
    """agent / runs / you / away seconds between t0 and t1, and the parts of each ("agent:
    thinking", "runs: engine", ...): thinking and writing as the transcript measured them
    (thinkingDurationMs, toolInputStreamMs; a reply's text by its time), the rest of the
    model's time "waiting on the model" (the request going out, the first token)"""
    tot = {"agent": 0.0, "runs": 0.0, "you": 0.0, "away": 0.0}
    part = {}

    def add(k, s):
        part[k] = part.get(k, 0.0) + s

    for a, b in zip(ev, ev[1:]):
        ta, tb = ts(a["timestamp"]), ts(b["timestamp"])
        if tb <= t0 or ta >= t1:
            continue
        ta, tb = max(ta, t0), min(tb, t1)
        g = max(0.0, tb - ta)
        ka, kb = kind(a), kind(b)
        if kb == "human":
            if g > away_s:
                tot["away"] += g
            else:
                tot["you"] += g
            continue
        if kb == "notice":
            cap = BG_CAP
            bucket = "runs"
            m = re.search(r"<task-id>(\w+)</task-id>", str((b.get("message") or {}).get("content", "")))
            sub = "runs: waiting on a background " + ((bg or {}).get(m.group(1), "run") if m else "run")
        elif ka == "tool" and kb == "result" and (
                str((b.get("permissionDecision") or {}).get("source", "")).startswith("user")
                or '"name": "AskUserQuestion"' in json.dumps((a.get("message") or {}).get("content"))):
            # a tool call waiting on the person: a permission they clicked, a question they answered
            if g > away_s:
                tot["away"] += g
            else:
                tot["you"] += g
                add("you: approving or answering", g)
            continue
        elif ka == "tool" and kb == "result":
            cap = AGENT_CAP
            bucket = "runs"
            sub = "runs: " + tool_kind(a)
        else:
            cap = AGENT_CAP
            bucket = "agent"
            sub = None
        used = min(g, cap)
        tot[bucket] += used
        tot["away"] += max(0.0, g - cap)
        if sub:
            add(sub, used)
            continue
        # the model's own time: what the record says it spent, the rest waiting on it
        k = kind(b)
        spent = 0.0
        if k == "tool":
            spent = float(b.get("toolInputStreamMs") or 0) / 1000.0
            add("agent: writing tool calls", min(spent, used))
        elif k == "text":
            c = (b.get("message") or {}).get("content") or []
            if any(isinstance(x, dict) and x.get("type") == "thinking" for x in c):
                spent = float(b.get("thinkingDurationMs") or 0) / 1000.0
                add("agent: thinking", min(spent, used))
            else:
                spent = used
                add("agent: writing replies", used)
        add("agent: waiting on the model (each step: the request out, the first word)", max(0.0, used - spent))
    tot["parts"] = part
    return tot


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, encoding="utf-8", errors="replace").stdout


def commits():
    """hash -> (unix time, subject); every commit on any branch, merges left out"""
    out = {}
    for line in git("log", "--all", "--no-merges", "--format=%H\x1f%ct\x1f%s").splitlines():
        p = line.split("\x1f")
        if len(p) == 3:
            out[p[0]] = (int(p[1]), p[2])
    return out


def game_of(h):
    names = set()
    for f in git("show", "--name-only", "--format=", h).splitlines():
        if f.endswith("EFFORT.md"):
            continue   # (this tool's own tables: a commit of them is no game's work)
        m = re.match(r"game/([^/]+)/", f)
        if m:
            names.add(m.group(1))
    return sorted(names)


def fmt(s):
    m = s / 60.0
    return "%.0f" % m if m >= 10 else "%.1f" % m


HEAD = "| date (UTC) | commit | change | agent | runs | you | active | away |\n|---|---|---|---|---|---|---|---|\n"


def row(r):
    subj = r["subject"].replace("|", "/")
    if len(subj) > 110:
        subj = subj[:107] + "..."
    t = r["t"]
    act = t["agent"] + t["runs"] + t["you"]
    return "| %s | %s | %s | %s | %s | %s | **%s** | %s |" % (
        dt.datetime.fromtimestamp(r["time"], dt.timezone.utc).strftime("%Y-%m-%d %H:%M"), r["hash"][:7], subj,
        fmt(t["agent"]), fmt(t["runs"]), fmt(t["you"]), fmt(act), fmt(t["away"]))


def write_table(path, title, rows):
    keep = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            m = re.match(r"\| [0-9-]+ [0-9:]+ \| ([0-9a-f]{7}) \|", line)
            if m:
                keep[m.group(1)] = line.rstrip("\n")
    for r in rows:
        keep[r["hash"][:7]] = row(r)
    lines = sorted(keep.values(), reverse=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# %s\n\n" % title)
        f.write("How long each change took, in minutes, from the Claude Code sessions that made it "
                "(`tools/effort.py`, which says how it is counted): **agent** thinking and writing, "
                "**runs** the tests, engine and git it waited on, **you** between its reply and "
                "your next message, **active** the three together. **away** is left out: gaps over "
                "10 minutes, and the rest of any step past its cap. Newest first; rows are kept "
                "once written.\n\n")
        f.write(HEAD)
        for l in lines:
            f.write(l + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--projects", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--since", help="only commits from this day (YYYY-MM-DD, UTC)")
    ap.add_argument("--last", type=int, help="only the last N commits found")
    ap.add_argument("--away", type=float, default=10.0, help="minutes of quiet that count as away")
    ap.add_argument("--print", action="store_true", help="print the rows, write nothing")
    ap.add_argument("--detail", action="store_true", help="print what the agent and run minutes were, per commit and in all")
    a = ap.parse_args()
    away_s = a.away * 60.0
    allc = commits()
    by_time = sorted(allc.items(), key=lambda kv: kv[1][0])
    rows = {}
    for path in glob.glob(os.path.join(a.projects, "*", "*.jsonl")):
        ev = load_session(path)
        bg = background(ev)
        if len(ev) < 2:
            continue
        start = ts(ev[0]["timestamp"])
        prev = start
        made = []
        for t_call, cmd in commit_calls(ev):
            # the commit it made: within a few minutes after the call, its subject in the command
            for h, (ct, subj) in by_time:
                if ct < t_call - 5 or ct > t_call + 600:
                    continue
                key = subj[:40]
                if key and key in cmd and h not in rows and h not in made:
                    made.append(h)
                    break
        for h in sorted(made, key=lambda h: allc[h][0]):
            ct, subj = allc[h]
            t = split(ev, prev, ct + 1, away_s, bg)
            rows[h] = {"hash": h, "time": ct, "subject": subj, "t": t, "session": os.path.basename(path)[:8]}
            prev = ct + 1
    out = sorted(rows.values(), key=lambda r: r["time"])
    if a.since:
        t_since = dt.datetime.fromisoformat(a.since).replace(tzinfo=dt.timezone.utc).timestamp()
        out = [r for r in out if r["time"] >= t_since]
    if a.last:
        out = out[-a.last:]
    if a.detail:
        allp = {}
        for r in out:
            p = r["t"]["parts"]
            for k, v in p.items():
                allp[k] = allp.get(k, 0.0) + v
            print("%s %s  %s" % (r["hash"][:7], r["subject"][:70], "  ".join(
                "%s %s" % (k.split(": ")[1], fmt(v)) for k, v in sorted(p.items(), key=lambda kv: -kv[1]) if v >= 6)))
        tot = sum(allp.values())
        print("\nIn all (%d commits, %s min of agent and runs):" % (len(out), fmt(tot)))
        for k, v in sorted(allp.items(), key=lambda kv: -kv[1]):
            print("  %-42s %6s min  %3.0f%%" % (k, fmt(v), 100.0 * v / max(tot, 1.0)))
        return
    if a.print:
        sys.stdout.write(HEAD)
        for r in reversed(out):
            print(row(r))
        tot = {k: sum(r["t"][k] for r in out) for k in ("agent", "runs", "you", "away")}
        print("\n%d commits: agent %s, runs %s, you %s min -- active %s; away %s (left out)" % (
            len(out), fmt(tot["agent"]), fmt(tot["runs"]), fmt(tot["you"]),
            fmt(tot["agent"] + tot["runs"] + tot["you"]), fmt(tot["away"])))
        return
    groups = {}
    for r in out:
        files = [f for f in git("show", "--name-only", "--format=", r["hash"]).splitlines() if f]
        if files and all(f.endswith("EFFORT.md") for f in files):
            continue   # (a commit of the tables alone)
        gs = game_of(r["hash"])
        for gname in (gs or [""]):
            groups.setdefault(gname, []).append(r)
    for gname, rs in groups.items():
        if gname and not os.path.isdir(os.path.join("game", gname)):
            continue   # (a game since deleted: its history goes with its folder)
        if gname:
            write_table(os.path.join("game", gname, "EFFORT.md"), "Effort: %s" % gname, rs)
        else:
            write_table("EFFORT.md", "Effort: the kit", rs)
        print("%s: %d rows" % (os.path.join("game", gname, "EFFORT.md") if gname else "EFFORT.md", len(rs)))


if __name__ == "__main__":
    main()
