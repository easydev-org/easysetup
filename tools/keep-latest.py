#!/usr/bin/env python3
"""Drop every setup except the newest version of its tool.

Versions are not comparable as strings (5.9 < 5.10; clang 21 vs java 21.0.12.1+1
have different shapes), so this compares the numeric segments and treats a
trailing build suffix like "+1" as a tie-breaker rather than as part of the
version.

    tools/keep-latest.py [--apply]

Without --apply it only reports what it would remove, because deleting entries
from a manifest is worth seeing first.
"""

import re
import sys
from collections import defaultdict

sys.path.insert(0, "/data/es")
import matrixlib2


def key(version):
    """A sortable key: numeric segments, then any trailing build tag."""
    # "21.0.12.1+1" -> ([21,0,12,1], [1]);  "5.9" -> ([5,9], [])
    main, _, build = version.partition("+")
    nums = []
    for part in re.split(r"[.\-]", main):
        m = re.match(r"^(\d+)$", part)
        nums.append(int(m.group(1)) if m else -1)
    bs = [int(x) for x in re.findall(r"\d+", build)]
    return (nums, bs)


def main(argv):
    apply = "--apply" in argv
    entries = matrixlib2.load("/data/es/matrix-nix.yml")

    by_tool = defaultdict(list)
    for e in entries:
        by_tool[e["tool"]].append(e)

    keep, drop = [], []
    for tool, es in by_tool.items():
        es_sorted = sorted(es, key=lambda e: key(e["version"]))
        newest = es_sorted[-1]
        keep.append(newest)
        for e in es_sorted[:-1]:
            drop.append(e)

    keep.sort(key=lambda e: (e["tool"], key(e["version"])))
    print("keeping %d, dropping %d" % (len(keep), len(drop)))
    print()
    print("dropped:")
    for e in sorted(drop, key=lambda e: (e["tool"], key(e["version"]))):
        print("   %-26s (newest is %s)"
              % (e["dir"], max(by_tool[e["tool"]], key=lambda x: key(x["version"]))["version"]))
    print()
    print("kept:")
    for e in keep:
        print("   %-26s %s" % (e["tool"], e["version"]))

    if not apply:
        print()
        print("rerun with --apply to rewrite matrix-nix.yml")
        return 0

    # Rewrite the manifest: keep the comment preamble, then one line per kept
    # entry, grouped the way the file already is. Regenerating the body from the
    # parsed entries loses the section comments, so those are preserved by
    # copying them from the original header.
    text = open("/data/es/matrix-nix.yml").read()
    header = text.split("setups:", 1)[0]
    body = ["setups:"]
    body.append("  # One version per tool: the newest nixpkgs exposes. Older ones are")
    body.append("  # deliberately not published - keeping every version meant 63")
    body.append("  # tarballs where 40 do, and nothing pinned an old one on purpose.")
    for e in keep:
        body.append('  - { tool: %-10s attr: "%s", version: "%s" }'
                    % (e["tool"] + ",", e["attr"], e["version"]))
    open("/data/es/matrix-nix.yml", "w").write(header + "\n".join(body) + "\n")
    print()
    print("matrix-nix.yml rewritten; run tools/gen-setups.py next")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
