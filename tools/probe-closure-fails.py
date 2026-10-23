"""Why can't these setups' closures be read from the binary cache?

compute-deps.py skips a setup it cannot resolve or whose closure it cannot read,
and skipping is silent enough that six python-package setups and terraform
vanished from the graph. Each failure mode needs a different fix, so this prints
them separately:

  * `nix eval .outPath` failing  -> the attribute does not exist under that name
  * `path-info --store cache` failing -> the path is not IN that cache, which
    happens for anything nixpkgs builds locally rather than substituting

    tools/probe-closure-fails.py
"""

import os
import subprocess
import sys

NIX = (os.environ.get("NIX_BIN")
       or ("/nix/var/nix/profiles/default/bin/nix"
           if os.path.exists("/nix/var/nix/profiles/default/bin/nix") else "nix"))
CACHE = "https://cache.nixos.org"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import matrixlib2  # noqa: E402


def run(a, timeout=300):
    return subprocess.run(a, capture_output=True, text=True, timeout=timeout)


def main(argv):
    entries = matrixlib2.load(os.path.join(ROOT, "matrix-nix.yml"))
    for e in entries:
        r = run([NIX, "eval", "--raw", e["attr"] + ".outPath"])
        if r.returncode != 0 or not r.stdout.strip():
            print("%-24s OUTPATH FAILED  %s" % (e["dir"], e["attr"]))
            msg = (r.stderr or "").strip().splitlines()
            for l in msg[-2:]:
                print("      ", l[:150])
            continue
        p = r.stdout.strip()
        c = run([NIX, "path-info", "--store", CACHE, "-r", p])
        if c.returncode != 0:
            print("%-24s CACHE MISS      %s" % (e["dir"], p))
            for l in (c.stderr or "").strip().splitlines()[-2:]:
                print("      ", l[:150])
    print("done")


if __name__ == "__main__":
    main(sys.argv)
