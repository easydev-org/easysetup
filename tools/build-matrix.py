#!/usr/bin/env python3
"""Write the build matrix for the release workflow, both architectures.

Replaces a heredoc that was nested inside an if/else inside a YAML block scalar.
That arrangement produced a list the workflow silently read as empty - the setup
job succeeded and scheduled nothing - which is the kind of failure that looks
like "everything is up to date" rather than like a bug.

    tools/build-matrix.py                 what changed, both architectures
    tools/build-matrix.py <only>          one setup, both architectures
"""

import json
import os
import pathlib
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import matrixlib2  # noqa: E402

ARCHES = ("amd64", "arm64")


def plan(arch):
    """The setups build-plan would build for one architecture."""
    env = dict(os.environ, ARCH=arch)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools/build-plan.py"),
                        "--outputs"],
                       capture_output=True, text=True, env=env, cwd=ROOT)
    if r.returncode != 0:
        return []
    try:
        return [e["name"] for e in json.loads(r.stdout).get("include", [])]
    except ValueError:
        return []


def main():
    # Careful with positional arguments: an earlier version took argv[1] as the
    # setup name, so `--arch amd64` was read as "the setup called --arch" and
    # produced an empty matrix with no error.
    args = sys.argv[1:]
    arches = ARCHES
    if "--arch" in args:
        i = args.index("--arch")
        if i + 1 >= len(args):
            sys.exit("--arch needs a value")
        arches = (args[i + 1],)
        del args[i:i + 2]
    only = args[0] if args else ""
    avail = {e["dir"]: e for e in matrixlib2.load(os.path.join(ROOT, "matrix-nix.yml"))}

    if only:
        # An explicit request always wins - exactly what was asked for, no
        # unchanged-set logic.
        names = sorted(p.stem for p in pathlib.Path(ROOT, "setups").glob("*.nix"))
        if only in names:
            picked = [only]
        else:
            hits = [n for n in names if n.startswith(only)]
            if len(hits) != 1:
                sys.exit("only=%r matches %d setups" % (only, len(hits)))
            picked = hits
        inc = [{"name": n, "arch": a}
               for n in picked for a in arches
               if n in avail and matrixlib2.available_on(avail[n], a)]
    else:
        inc = []
        for a in arches:
            for n in plan(a):
                inc.append({"name": n, "arch": a})

    print(json.dumps({"include": inc}))


if __name__ == "__main__":
    main()
