#!/usr/bin/env python3
"""Turn the unpacked trees into the numbers that decide the delta question.

For every pair of setups: how many bytes would a shared base save, expressed
both absolutely and as a fraction of what the consumer downloads today.

The comparison that matters is not "how big is glibc" but "if I ask for these N
tools, how much of the total download is a duplicate". That number is what a
delta scheme would recover, and it is bounded above by the size of the shared
paths times (N-1).
"""

import os
import sys
from itertools import combinations

ROOT = "/data/delta/x"


def sizes(setup):
    """Map store-path name -> bytes for one unpacked setup."""
    store = os.path.join(ROOT, setup, "nix", "store")
    out = {}
    if not os.path.isdir(store):
        return out
    for name in os.listdir(store):
        p = os.path.join(store, name)
        total = 0
        if os.path.islink(p):
            continue
        for dirpath, _dirnames, filenames in os.walk(p):
            for f in filenames:
                fp = os.path.join(dirpath, f)
                try:
                    if not os.path.islink(fp):
                        total += os.path.getsize(fp)
                except OSError:
                    pass
        out[name] = total
    return out


def mb(n):
    return n / 1048576.0


def main(argv):
    setups = [d for d in sorted(os.listdir(ROOT))
              if os.path.isdir(os.path.join(ROOT, d))]
    if len(setups) < 2:
        sys.exit("need at least two unpacked setups under %s" % ROOT)

    data = {s: sizes(s) for s in setups}

    print("== each setup's unpacked size ==")
    for s in setups:
        print("  %-24s %4d paths  %8.1f MB"
              % (s, len(data[s]), mb(sum(data[s].values()))))

    print()
    print("== shared across every setup ==")
    common = set.intersection(*[set(v) for v in data.values()])
    common_bytes = sum(data[setups[0]].get(p, 0) for p in common)
    for p in sorted(common, key=lambda x: -data[setups[0]].get(x, 0)):
        print("  %8.1f MB  %s" % (mb(data[setups[0]].get(p, 0)), p.split("-", 1)[-1]))
    print("  shared total: %.1f MB" % mb(common_bytes))

    print()
    print("== what a shared base would save, for a few real combinations ==")
    # The saving is the shared bytes counted once instead of N times.
    groups = [
        ["jq-1.8.2", "yq-4.54.1"],
        ["jq-1.8.2", "yq-4.54.1", "node-26.12.0"],
        ["node-26.12.0", "python-3.15.0", "php-8.5.11"],
        setups,
    ]
    for g in groups:
        g = [x for x in g if x in data]
        if len(g) < 2:
            continue
        naive = sum(sum(data[s].values()) for s in g)
        inter = set.intersection(*[set(data[s]) for s in g])
        shared = sum(data[g[0]].get(p, 0) for p in inter)
        save = shared * (len(g) - 1)
        print("  %-58s naive %7.1f MB  save %6.1f MB (%4.1f%%)"
              % (" + ".join(x.split("-")[0] for x in g), mb(naive),
                 mb(save), 100.0 * save / naive if naive else 0))

    print()
    print("== pairing view: biggest single-tool saving ==")
    rows = []
    for a, b in combinations(setups, 2):
        inter = set(data[a]) & set(data[b])
        shared = sum(data[a].get(p, 0) for p in inter)
        naive = sum(data[a].values()) + sum(data[b].values())
        rows.append((shared, a, b, naive))
    for shared, a, b, naive in sorted(rows, reverse=True)[:6]:
        print("  %-20s + %-20s shared %6.1f MB  of %7.1f MB (%4.1f%%)"
              % (a.split("-")[0], b.split("-")[0], mb(shared), mb(naive),
                 100.0 * shared / naive if naive else 0))


if __name__ == "__main__":
    main(sys.argv)
