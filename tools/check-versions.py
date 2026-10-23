#!/usr/bin/env python3
"""Compare matrix-nix.yml's recorded version with what the locked nixpkgs gives.

The manifest's version field is informational, but a stale one produces a release
whose tag and directory disagree with the tarball inside - and once published, a
tag cannot be quietly corrected. This checks every entry against
`nix eval .#<name>.version`, which reads through flake.lock, so drift surfaces
here rather than in a release.

    tools/check-versions.py [--fix]

--fix rewrites the manifest in place. It is opt-in because a bulk rewrite of a
hand-formatted file is exactly the kind of change that should be deliberate.
"""

import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import matrixlib2  # noqa: E402

# Resolve nix rather than assuming PATH: under a composite action it is installed
# by install-nix-action, and locally it may only be at its profile path.
NIX = (os.environ.get("NIX_BIN")
       or ("/nix/var/nix/profiles/default/bin/nix"
           if os.path.exists("/nix/var/nix/profiles/default/bin/nix") else "nix"))


def actual_version(name):
    # flake.nix exposes a `versions.<name>` tree because a plain package has no
    # flake-level `version` attribute; `.#<name>.version` simply does not resolve.
    r = subprocess.run(
        [NIX, "eval", "--raw", ".#versions.%s" % name],
        cwd=str(ROOT), capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        return None
    return r.stdout.strip()


def main(argv):
    fix = "--fix" in argv
    entries = matrixlib2.load(str(ROOT / "matrix-nix.yml"))
    text = (ROOT / "matrix-nix.yml").read_text()
    drift = []

    for e in entries:
        got = actual_version(e["dir"])
        if got is None:
            print("MISSING  %-24s nix cannot evaluate it" % e["dir"])
            drift.append(e)
            continue
        if got != e["version"]:
            print("DRIFT    %-24s manifest=%s nix=%s"
                  % (e["dir"], e["version"], got))
            drift.append((e, got))

    if not drift:
        print("all %d entries match the locked nixpkgs" % len(entries))
        return 0

    print()
    print("%d entries differ" % len(drift))
    if not fix:
        print("rerun with --fix to rewrite matrix-nix.yml (and regenerate setups/)")
        return 1

    # Rewrite the version field for each drifting line. Entries are one per line,
    # so this is a per-line substitution anchored on the attr, not a parser.
    for item in drift:
        if isinstance(item, tuple):
            e, got = item
            old = 'attr: "%s", version: "%s"' % (e["attr"], e["version"])
            new = 'attr: "%s", version: "%s"' % (e["attr"], got)
            if old in text:
                text = text.replace(old, new)
                print("fixed %s -> %s" % (e["dir"], got))
            else:
                print("could not locate the line for %s" % e["dir"])
        else:
            print("cannot fix %s automatically" % item["dir"])
    (ROOT / "matrix-nix.yml").write_text(text)
    print("matrix-nix.yml updated; run tools/gen-setups.py to refresh setups/")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
