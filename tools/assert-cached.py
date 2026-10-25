#!/usr/bin/env python3
"""Prove that every setup in the manifest is substitutable, for both architectures.

This is the guarantee, checked as a fact rather than trusted as a convention:
every one of the project's tarballs contains bytes cache.nixos.org built, never
bytes we built.

    tools/assert-cached.py            both architectures
    tools/assert-cached.py arm64      one

A setup counts as substitutable when its own output path has a narinfo in the
cache AND every path in its closure does too. Checking only the top path is not
enough: a setup's own build can be cached while a dependency is not, and the
dependency is the thing that would compile.

Members of the `base` set are checked too - they are shipped inside every tarball
that depends on them, so a missing one breaks all of them.

Non-zero exit if anything would have to be compiled, which is what the release
workflow gates on.
"""

import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import matrixlib2  # noqa: E402

NIX = (os.environ.get("NIX_BIN")
       or ("/nix/var/nix/profiles/default/bin/nix"
           if os.path.exists("/nix/var/nix/profiles/default/bin/nix") else "nix"))
CACHE = "https://cache.nixos.org"
SYSTEMS = {"amd64": "x86_64-linux", "arm64": "aarch64-linux"}


def run(args, timeout=300):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def narinfo_codes(paths):
    """The cache's HTTP status for each store path, fetched in parallel.

    Asking one at a time is thousands of round trips - a full closure set is a few
    thousand paths - so this batches through xargs.
    """
    if not paths:
        return {}
    hashes = sorted({os.path.basename(p).split("-", 1)[0] for p in paths})
    listing = "\n".join(hashes)
    r = subprocess.run(
        ["xargs", "-P", "16", "-I", "{}",
         "sh", "-c", 'printf "%s " "{}"; curl -s -o /dev/null -w "%{http_code}\\n" '
                     + CACHE + '/{}.narinfo'],
        input=listing, capture_output=True, text=True, timeout=1800)
    out = {}
    for line in r.stdout.splitlines():
        f = line.split()
        if len(f) == 2:
            out[f[0]] = f[1]
    return out


def closure_of(path):
    """Every path in the closure, from the cache's own metadata.

    Read with --store CACHE: if the cache cannot answer, the setup is not
    substitutable and closure_of returns None, which the caller treats as a
    failure rather than discovering it later at build time.
    """
    r = run([NIX, "path-info", "--store", CACHE, "-r", path], timeout=600)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    return [x for x in r.stdout.splitlines() if x.strip()]


def main(argv):
    want = [a for a in argv if a in SYSTEMS] or list(SYSTEMS)
    manifest = matrixlib2.load(os.path.join(ROOT, "matrix-nix.yml"))
    failures = 0

    for arch in want:
        system = SYSTEMS[arch]
        graph = json.load(open(matrixlib2.closures_path(ROOT, arch)))
        entries = [e for e in manifest if matrixlib2.available_on(e, arch)]
        print("== %s: %d setups ==" % (arch, len(entries)))

        # One closure walk per setup's own output, plus the shared base set.
        all_paths = set(graph["base"])
        unreadable = []
        for e in entries:
            entry = graph["setups"].get(e["dir"])
            if not entry:
                unreadable.append((e["dir"], "absent from the graph"))
                continue
            c = closure_of(entry["store"])
            if c is None:
                unreadable.append((e["dir"], "cache cannot describe its closure"))
                continue
            all_paths.update(c)

        print("   store paths to check: %d" % len(all_paths))
        codes = narinfo_codes(all_paths)
        missing = {h: c for h, c in codes.items() if c != "200"}

        if unreadable:
            print("   NOT SUBSTITUTABLE (%d):" % len(unreadable))
            for name, why in unreadable[:20]:
                print("     %-30s %s" % (name, why))
            failures += len(unreadable)

        if missing:
            print("   %d path(s) are not in the cache:" % len(missing))
            for h, c in list(missing.items())[:20]:
                print("     %s  -> %s" % (h, c))
            failures += len(missing)

        if not unreadable and not missing:
            print("   every path is in cache.nixos.org")

    print()
    if failures:
        print("FAILED: %d problem(s) - these setups must not be published" % failures)
        return 1
    print("OK: everything that would be published is already built and cached")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
