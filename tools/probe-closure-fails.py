#!/usr/bin/env python3
"""Why is each unbuildable setup unbuildable? One line per reason.

compute-deps.py skips a setup it cannot resolve or whose closure the cache cannot
describe. Skipping is silent enough that six python-package setups and terraform
once vanished from the graph without anyone noticing, so every run prints this.

The reasons are kept apart because each needs a different response:

  BROKEN           nixpkgs marks it broken for this platform (swift on aarch64)
  PLATFORM         no derivation for this system at all
  NOT CACHED       the output exists but cache.nixos.org has never built it,
                   so publishing it would mean compiling - which is not allowed
  ATTRIBUTE GONE   our flake has no such setup (a manifest/gen-setups mismatch)

The previous version of this script was itself broken in the way it was written
to detect: it asked for `nixpkgs#<attr>` by attribute rather than our flake by
directory name, and passed no --system, so it reported failures that were neither
of the above. Asking one set of questions and reporting another is worse than not
reporting.

    tools/probe-closure-fails.py             both architectures
    ARCH=arm64 tools/probe-closure-fails.py
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import matrixlib2  # noqa: E402

NIX = (os.environ.get("NIX_BIN")
       or ("/nix/var/nix/profiles/default/bin/nix"
           if os.path.exists("/nix/var/nix/profiles/default/bin/nix") else "nix"))
SYSTEMS = {"amd64": "x86_64-linux", "arm64": "aarch64-linux"}


def run(a, timeout=600):
    return subprocess.run(a, capture_output=True, text=True, timeout=timeout)


def diagnose(entry, arch, system):
    """One setup's verdict, or None when it is fine."""
    name = entry["dir"]
    expr = ('let f = builtins.getFlake (toString ./.); '
            'p = f.inputs.nixpkgs.legacyPackages.%s; '
            'in (import (./setups + "/%s.nix") { pkgs = p; }).outPath'
            % (system, name))
    r = run([NIX, "eval", "--raw", "--impure", "--expr", expr])
    if r.returncode != 0:
        err = (r.stderr or "").lower()
        if "is broken" in err:
            return "BROKEN", "nixpkgs marks it broken for %s" % system
        if "does not provide attribute" in err or "not supported" in err:
            return "PLATFORM", "no derivation for %s" % system
        last = (r.stderr or "").strip().splitlines()
        return "ATTRIBUTE GONE", (last[-1][:110] if last else "eval failed")

    out = r.stdout.strip()
    # Is the output itself in the cache?
    h = os.path.basename(out).split("-", 1)[0]
    c = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
             "https://cache.nixos.org/%s.narinfo" % h])
    if c.stdout.strip() != "200":
        return "NOT CACHED", "cache answers %s for its output" % c.stdout.strip()

    # And can the cache describe its whole closure? A cached output sitting on an
    # uncached dependency still means a compile.
    pi = run([NIX, "path-info", "--store", "https://cache.nixos.org", "-r", out])
    if pi.returncode != 0 or not pi.stdout.strip():
        return "NOT CACHED", "cache cannot describe its closure"
    return None


def main(argv):
    want = [a for a in argv if a in SYSTEMS] or [
        os.environ.get("ARCH", "amd64")]
    manifest = matrixlib2.load(os.path.join(ROOT, "matrix-nix.yml"))
    bad = 0
    for arch in want:
        system = SYSTEMS[arch]
        entries = [e for e in manifest if matrixlib2.available_on(e, arch)]
        skipped = [e for e in manifest if not matrixlib2.available_on(e, arch)]
        print("== %s: %d setups to publish ==" % (arch, len(entries)))
        for e in skipped:
            print("%-34s EXCLUDED       only_arch, so not published for %s"
                  % (e["dir"], arch))
        for e in entries:
            v = diagnose(e, arch, system)
            if v:
                reason, detail = v
                print("%-34s %-15s %s" % (e["dir"], reason, detail))
                bad += 1
        print()
    if bad:
        print("%d setup(s) cannot be published as-is" % bad)
    else:
        print("every setup for %s resolves and is fully cached" % ", ".join(want))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
