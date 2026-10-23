#!/usr/bin/env python3
"""Which paths in a closure actually account for the size?

`nix path-info -S` prints one line per store path with its narSize; sorting that
by size answers "why is this 5.8 GB" instead of leaving it a mystery.

    tools/why-big.py nixpkgs#swift [n]
"""

import subprocess
import sys

NIX = "/nix/var/nix/profiles/default/bin/nix"


def main(argv):
    attr = argv[1]
    top = int(argv[2]) if len(argv) > 2 else 15

    r = subprocess.run([NIX, "path-info", "-rS", "--json", attr],
                       capture_output=True, text=True, timeout=900)
    if r.returncode != 0:
        sys.exit(r.stderr[-400:])

    import json
    out = r.stdout
    d = json.loads(out[out.find("{"):])
    rows = sorted(((v.get("narSize", 0), k) for k, v in d.items()), reverse=True)
    total = sum(s for s, _ in rows)

    print("%s: %d paths, %.1f MB total unpacked"
          % (attr, len(rows), total / 1048576))
    print()
    print("%-9s %6s  %s" % ("size", "cum%", "path"))
    cum = 0
    for size, path in rows[:top]:
        cum += size
        name = path.split("-", 1)[1] if "-" in path else path
        print("%7.1f MB %5.1f%%  %s" % (size / 1048576, 100.0 * cum / total, name))
    print()
    print("top %d account for %.1f%% of the closure"
          % (top, 100.0 * cum / total))


if __name__ == "__main__":
    main(sys.argv)
