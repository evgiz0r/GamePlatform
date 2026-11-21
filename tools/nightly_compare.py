#!/usr/bin/env python3
"""Compare tonight's verdicts with last night's, for the nightly checks
(.github/workflows/nightly_checks.yml). Each game's tests/nightly.sh writes verdicts.txt,
one line per verdict, "<label>: <value> [OVER]" or "REGRESS <name>: PASS|FAIL|NO VERDICT".

    tools/nightly_compare.py <last night's verdicts.txt or -> <tonight's verdicts.txt>

Prints the lines that changed, in Markdown, and exits 1 when something got worse: a line
saying FAIL, OVER, NO VERDICT or SCRIPT ERROR that last night did not have, or a count that
rose. A missing last night (the first run) compares with nothing and exits 0.
"""
import re
import sys

BAD = ("FAIL", "OVER", "NO VERDICT", "SCRIPT ERROR")


def read(path):
    rows = {}
    if path == "-":
        return rows
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if ":" in line:
                    k, v = line.split(":", 1)
                    rows[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return rows


def number(v):
    m = re.match(r"^\D*?(-?\d+(?:\.\d+)?)", v)
    return float(m.group(1)) if m else None


def main():
    prev, cur = read(sys.argv[1]), read(sys.argv[2])
    worse, better, other = [], [], []
    for k, v in cur.items():
        was = prev.get(k)
        if was == v:
            continue
        line = "- **%s**: %s%s" % (k, v, "" if was is None else " (last night: %s)" % was)
        bad_now = any(b in v for b in BAD)
        bad_before = was is not None and any(b in was for b in BAD)
        n, n0 = number(v), (number(was) if was is not None else None)
        if not prev:
            (worse if bad_now else other).append(line)
        elif bad_now and not bad_before:
            worse.append(line)
        elif bad_before and not bad_now:
            better.append(line)
        elif n is not None and n0 is not None and n > n0 and not k.startswith("REGRESS"):
            worse.append(line)
        elif n is not None and n0 is not None and n < n0:
            better.append(line)
        else:
            other.append(line)
    gone = [k for k in prev if k not in cur]
    if not prev:
        print("_No earlier night to compare with: tonight's verdicts are the baseline._\n")
        if worse:
            print("### Not passing\n" + "\n".join(worse) + "\n")
        return 0
    if worse:
        print("### Worse than last night\n" + "\n".join(worse) + "\n")
    if better:
        print("### Better than last night\n" + "\n".join(better) + "\n")
    if other:
        print("### Changed\n" + "\n".join(other) + "\n")
    if gone:
        print("### No longer reported\n" + "\n".join("- " + k for k in gone) + "\n")
    if not (worse or better or other or gone):
        print("_Every verdict the same as last night._\n")
    return 1 if worse else 0


if __name__ == "__main__":
    sys.exit(main())
