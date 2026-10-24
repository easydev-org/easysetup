#!/usr/bin/env python3
"""Decide which setups need building, instead of rebuilding all 155 every time.

A setup's tarball is a pure function of four inputs, so it is only worth
rebuilding when one of them changes:

  1. setups/<dir>.nix      what to build
  2. its own path list     which paths its tarball carries (a delta change)
  3. flake.lock            which nixpkgs everything is built from
  4. its dependencies      recursively, because a delta depends on theirs

Anything not covered by those four cannot change the bytes, so rebuilding it is
pure waste - which is what a 157-job run of a 155-setup manifest mostly is.

Fingerprints are recorded in build-state.json after a successful publish. That
file is a cache, not a source of truth: it is always cross-checked against
whether the release actually exists, so losing it (or a failed publish that
wrote nothing) costs at most one redundant rebuild rather than a missing
artifact.

    tools/build-plan.py --outputs            write the matrix for the workflow
    tools/build-plan.py --report             say what would be built and why
    tools/build-plan.py --record <dir>...    after a successful publish
"""

import hashlib
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import matrixlib2  # noqa: E402

STATE = os.path.join(ROOT, "build-state.json")


def read(path, default=None):
    try:
        return open(path, "rb").read()
    except OSError:
        return default


def h(*parts):
    m = hashlib.sha256()
    for p in parts:
        m.update(p if isinstance(p, bytes) else str(p).encode())
        m.update(b"\0")
    return m.hexdigest()[:16]


def release_exists(tag):
    """Does GitHub already hold this release?"""
    token = ""
    hosts = os.path.expanduser("~/.config/gh/hosts.yml")
    if os.path.exists(hosts):
        for line in open(hosts):
            if "oauth_token:" in line:
                token = line.split("oauth_token:")[1].strip()
                break
    if not token:
        return True          # cannot check; trust the state file
    repo = os.environ.get("GITHUB_REPOSITORY", "easydev-org/easysetup")
    r = subprocess.run(
        ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
         "--max-time", "30", "-H", "Authorization: Bearer " + token,
         "https://api.github.com/repos/%s/releases/tags/%s" % (repo, tag)],
        capture_output=True, text=True)
    return r.stdout.strip() == "200"


def main(argv):
    outputs = "--outputs" in argv
    report = "--report" in argv
    record = argv[argv.index("--record") + 1:] if "--record" in argv else []

    entries = matrixlib2.load(os.path.join(ROOT, "matrix-nix.yml"))
    closures = json.load(open(os.path.join(ROOT, "closures.json")))
    lock = read(os.path.join(ROOT, "flake.lock"), b"")

    by_dir = {e["dir"]: e for e in entries}
    setups = closures["setups"]

    # Fingerprint each setup bottom-up: a delta's bytes depend on what its
    # dependencies provide, so a change deep in the graph has to propagate up.
    fp = {}
    reasons = {}

    def fingerprint(name, stack=()):
        if name in fp:
            return fp[name]
        if name in stack:
            return "cycle"
        entry = by_dir.get(name)
        if entry is None:
            return "missing"
        sfile = read(os.path.join(ROOT, "setups", name + ".nix"), b"")
        # `own` is the path list this tarball carries. If the derived graph
        # changes - a dependency appears, or base grows - the tarball changes
        # even though the .nix file did not.
        own = "\n".join(setups.get(name, {}).get("own", []))
        deps = sorted(setups.get(name, {}).get("deps", []))
        depfp = "".join(fingerprint(d, stack + (name,)) for d in deps)
        fp[name] = h(sfile, own, lock, depfp)
        return fp[name]

    state = {}
    raw = read(STATE, b"")
    if raw:
        try:
            state = json.loads(raw)
        except Exception:
            state = {}

    need = []
    for e in entries:
        name = e["dir"]
        cur = fingerprint(name)
        old = state.get(name)
        if old is None:
            reasons[name] = "never built (no state)"
            need.append(name)
        elif cur != old:
            reasons[name] = "inputs changed"
            need.append(name)
        elif not release_exists(e["dir"]):
            reasons[name] = "release missing from GitHub"
            need.append(name)

    if record:
        for name in record:
            state[name] = fingerprint(name)
        with open(STATE, "w") as f:
            json.dump(state, f, indent=1, sort_keys=True)
        print("recorded %d setup(s); %d in state" % (len(record), len(state)))
        return 0

    if report or not outputs:
        unchanged = len(entries) - len(need)
        print("%d to build, %d unchanged" % (len(need), unchanged))
        for name in sorted(need):
            print("  %-32s %s" % (name, reasons[name]))

    if outputs:
        # The workflow reads this as the matrix. Keep the same shape the existing
        # matrix step produces so the build job needs no changes.
        print(json.dumps({"include": [{"name": n} for n in sorted(need)]}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
