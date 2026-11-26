#!/usr/bin/env python3
"""Compare two fingerprint dumps (tests/fingerprint.gd's OUT/fp_*.txt) as multisets of lines:
how many of each kind are only in one of them.  python3 fp_compare.py A.txt B.txt"""
import sys, collections
a = collections.Counter(open(sys.argv[1]).read().split('\n'))
b = collections.Counter(open(sys.argv[2]).read().split('\n'))
only_a, only_b = a - b, b - a
for name, d in (('only in A', only_a), ('only in B', only_b)):
    kinds = collections.Counter(l.split(' ')[0] + ('' if not l.startswith('FPNODE') else ' ' + l.split(' ')[1]) for l in d.elements())
    print(name, sum(d.values()), dict(kinds))
if len(sys.argv) > 3:
    # A and B two runs of the code before: what they agree on must all be in C
    c = collections.Counter(open(sys.argv[3]).read().split('\n'))
    stable = a & b
    lost = stable - c
    print('stable in both A and B:', sum(stable.values()), '-- missing from C:', sum(lost.values()), dict(collections.Counter(l.split(' ')[0] for l in lost.elements())))
    for l in list(lost.elements())[:10]:
        print('  ', l)
