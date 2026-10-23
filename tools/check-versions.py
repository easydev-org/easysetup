#!/usr/bin/env python3
"""Compare every manifest version against what nix actually reports.

The manifest's version is not just documentation: build-nixpkg.sh refuses to
build when the two disagree, because a tarball named 1.140.0 while nix built
1.140.06880 would mislabel a release. Two entries were wrong in exactly that way
(ccls, vscode-langservers) because the probe that produced them printed an
11-character version column and truncated longer versions.

    tools/check-versions.py           report mismatches
    tools/check-versions.py --fix     rewrite the manifest to match nix
"""

import os
import re
import subprocess
import sys

NIX = (os.environ.get("NIX_BIN")
       or ("/nix/var/nix/profiles/default/bin/nix"
           if os.path.exists("/nix/var/nix/profiles/default/bin/nix") else "nix"))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import matrixlib2  # noqa: E402


def actual(attr):
    r = subprocess.run([NIX, "eval", "--raw", attr + ".version"],
                       capture_output=True, text=True, timeout=300)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    return r.stdout.strip()


def main(argv):
    fix = "--fix" in argv
    path = os.path.join(ROOT, "matrix-nix.yml")
    text = open(path).read()
    entries = matrixlib2.load(path)

    bad = []
    for e in entries:
        # `base` is glibc, whose .version is the full 2.44-57; the manifest
        # records 2.44 for readability, so it is skipped rather than special-cased
        # everywhere else.
        if e["tool"] == "base":
            continue
        v = actual(e["attr"])
        if v is None:
            print("%-26s %-12s cannot read .version" % (e["dir"], e["version"]))
            continue
        if v != e["version"]:
            bad.append((e, v))
            print("%-26s manifest %-14s nix %s" % (e["dir"], e["version"], v))

    if not bad:
        print("all %d entries match" % len(entries))
        return 0

    print()
    print("%d mismatch(es)" % len(bad))
    if not fix:
        print("rerun with --fix to update the manifest")
        return 1

    for e, v in bad:
        line = re.compile(
            r'(- \{ tool: %s,\s+attr: "%s", version: ")[^"]*(" \})'
            % (re.escape(e["tool"]), re.escape(e["attr"])))
        new_text, n = line.subn(lambda m: m.group(1) + v + m.group(2), text)
        if n != 1:
            print("could not rewrite %s (%d matches)" % (e["dir"], n))
            continue
        text = new_text
        print("fixed %-26s -> %s" % (e["dir"], v))
    open(path, "w").write(text)
    print("manifest updated; run tools/gen-setups.py")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
