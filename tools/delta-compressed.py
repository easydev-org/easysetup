#!/usr/bin/env python3
"""How much of the DOWNLOAD (not the unpacked size) is the shared base?

The unpacked numbers overstate the saving, because glibc is mostly large
uncompressible-in-place binaries but a tarball of it still compresses. What a
consumer pays is compressed bytes, so the decision has to be made on those.

Method: compress each setup's shared store paths on their own and compare that
with the whole tarball's size.
"""

import os
import subprocess
import sys

W = "/data/delta"
X = os.path.join(W, "x")
SETUPS = ["jq-1.8.2", "yq-4.54.1", "node-26.12.0",
          "python-3.15.0", "php-8.5.11", "cmake-4.4.4"]


def mb(n):
    return n / 1048576.0


def tarball_size(setup):
    p = os.path.join(W, "%s-debian-trixie-amd64.tar.zst" % setup)
    return os.path.getsize(p) if os.path.exists(p) else 0


def compressed_glibc(setup, names):
    """Compress just the paths every setup shares, as a base tarball would."""
    store = os.path.join(X, setup, "nix", "store")
    if not os.path.isdir(store):
        return 0
    paths = [os.path.join(store, c) for c in names
             if os.path.isdir(os.path.join(store, c))]
    if not paths:
        return 0
    out = "/tmp/base-test.zst"
    args = ["tar", "-cf", "-", "-C", os.path.join(X, setup, "nix"), "store"]
    # Restrict the archive to the shared subtrees by staging them first.
    stage = "/tmp/base-stage"
    subprocess.run(["rm", "-rf", stage], check=False)
    os.makedirs(os.path.join(stage, "nix", "store"), exist_ok=True)
    # Nix store directories are mode 0555, so cp -a cannot create them inside a
    # staging tree it owns. Copy the CONTENTS and restore permissions after.
    for p in paths:
        dest = os.path.join(stage, "nix", "store", os.path.basename(p))
        subprocess.run(["cp", "-rL", p, dest], check=False)
        subprocess.run(["chmod", "-R", "u+w", dest], check=False)
    t = subprocess.Popen(["tar", "-cf", "-", "-C", stage, "."],
                         stdout=subprocess.PIPE)
    z = subprocess.Popen(["zstd", "-3", "-T0", "--quiet", "-o", out],
                         stdin=t.stdout)
    t.stdout.close()
    z.wait()
    t.wait()
    sz = os.path.getsize(out) if os.path.exists(out) else 0
    subprocess.run(["rm", "-rf", stage, out], check=False)
    return sz


def main(argv):
    print("== download cost per setup ==")
    total = 0
    rows = []
    for s in SETUPS:
        t = tarball_size(s)
        total += t
        rows.append((s, t))
        print("  %-22s %7.1f MB" % (s, mb(t)))
    print("  %-22s %7.1f MB (naive total)" % ("", mb(total)))

    # Which store paths every setup shares is a fact about the artifacts, so read
    # it from them rather than hard-coding a name list that goes stale whenever
    # glibc moves a patch release.
    stores = {}
    for s in SETUPS:
        d = os.path.join(X, s, "nix", "store")
        stores[s] = set(os.listdir(d)) if os.path.isdir(d) else set()
    common = sorted(set.intersection(*stores.values())) if stores else []
    if not common:
        sys.exit("no common store paths found; are the setups unpacked?")
    print()
    print("== shared paths (from the artifacts) ==")
    for c in common:
        print("   ", c.split("-", 1)[-1])

    print()
    print("== what the shared base weighs, compressed ==")
    base = compressed_glibc(SETUPS[0], common)
    print("  base tarball (glibc + its 3 deps): %.1f MB" % mb(base))

    print()
    print("== net saving if every setup dropped the base ==")
    n = len(SETUPS)
    # Each setup drops the base and downloads it once instead.
    after = base + (total - n * base)
    saved = total - after
    print("  naive             : %7.1f MB" % mb(total))
    print("  with a shared base: %7.1f MB" % mb(after))
    print("  saving            : %7.1f MB (%.1f%%)" % (mb(saved), 100.0 * saved / total))

    print()
    print("== the same for a small two-tool job ==")
    two = [r for r in rows if r[0] in ("jq-1.8.2", "yq-4.54.1")]
    tt = sum(r[1] for r in two)
    after2 = base + (tt - 2 * base)
    saved2 = tt - after2
    print("  jq + yq naive     : %7.1f MB" % mb(tt))
    print("  with a shared base: %7.1f MB" % mb(after2))
    print("  saving            : %7.1f MB (%.1f%%)" % (mb(saved2), 100.0 * saved2 / tt))


if __name__ == "__main__":
    main(sys.argv)
