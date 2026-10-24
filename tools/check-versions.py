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


def actual(attr, arch):
    """What version nix reports for this attribute, on this architecture.

    Evaluated through OUR flake, not `nixpkgs#...`.

    This was the source of a false alarm that read like a real bug: the manifest
    pins versions from flake.lock, while `nixpkgs#x` resolves through NIX_PATH's
    channel - whatever the channel points at *today*. The two drift apart as soon
    as the channel advances, and thirteen entries then "disagreed" with nix while
    being perfectly correct for the revision the tarballs are actually built
    from. It surfaced during the arm64 work only because that run happened after
    a channel update.
    """
    system = {"amd64": "x86_64-linux", "arm64": "aarch64-linux"}[arch]
    name = attr.split("#", 1)[-1]
    expr = ('((builtins.getFlake (toString ./.)).inputs.nixpkgs'
            '.legacyPackages.%s.%s).version' % (system, name))
    r = subprocess.run([NIX, "eval", "--raw", "--impure", "--expr", expr],
                       capture_output=True, text=True, timeout=300)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    return r.stdout.strip()


def main(argv):
    fix = "--fix" in argv
    arch = os.environ.get("ARCH", "amd64")
    path = os.path.join(ROOT, "matrix-nix.yml")
    text = open(path).read()
    # Only the setups this architecture actually has: swift has no aarch64
    # derivation, so asking for its version there fails for a reason that is not
    # a mismatch.
    entries = [e for e in matrixlib2.load(path)
               if matrixlib2.available_on(e, arch)]
    print("checking %d setups for %s" % (len(entries), arch))

    bad = []
    for e in entries:
        # `base` is glibc, whose .version is the full 2.44-57; the manifest
        # records 2.44 for readability, so it is skipped rather than special-cased
        # everywhere else.
        if e["tool"] == "base":
            continue
        v = actual(e["attr"], arch)
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
        # A suffixed entry carries a `suffix:` field after the version, so the
        # pattern has to allow for it - otherwise the rewrite would not match and
        # the mismatch would be reported forever without being fixed.
        line = re.compile(
            r'(- \{ tool: %s,\s+attr: "%s", version: ")[^"]*(")' 
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
