#!/usr/bin/env python3
"""bump.py — find setups whose pinned version is behind upstream.

    bump.py --check     report stale entries, exit 1 if any (for CI)
    bump.py --apply     rewrite matrix.yml with the new pins

Each entry tracks ONE upstream release line, derived from its own pinned
version, so several versions of one tool never fight:

    node 22.23.4   -> newest 22.x
    python 3.12.15 -> newest 3.12.x
    go 1.24.13     -> newest 1.24.x
    java 21.0.12+101 -> newest 21 GA

A bump rewrites the version AND the artifact name (the asset carries the
version) and CLEARS the sha256, because a different file cannot match the old
digest. The release workflow re-pins it after the build.

Parsing goes through matrixlib, the same module install.sh and the release job
use, so there is one definition of the file's shape rather than three.
"""

import argparse
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import matrixlib  # noqa: E402

MATRIX = ROOT / "matrix.yml"


def http_json(url, tries=4):
    last = None
    for _ in range(tries):
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": "easysetup-bump",
                "Accept": "application/json",
            })
            with urllib.request.urlopen(req, timeout=45) as r:
                return json.load(r)
        except Exception as e:      # noqa: BLE001 - a feed being down is not fatal
            last = e
    raise last


def vkey(v):
    """Sort key for dotted versions with an optional +build suffix."""
    main, _, build = v.partition("+")
    return ([int(x) for x in re.findall(r"\d+", main)],
            [int(x) for x in re.findall(r"\d+", build)])


# --- what the upstream feeds say -------------------------------------------

def newest_node(major):
    for rel in http_json("https://nodejs.org/dist/index.json"):
        v = rel["version"].lstrip("v")
        if v.split(".")[0] == major and "linux-x64" in rel.get("files", []):
            return v
    return None


def newest_python(minor):
    rel = http_json("https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest")
    best = None
    for a in rel["assets"]:
        n = a["name"]
        if not n.startswith("cpython-"):
            continue
        if not n.endswith("-x86_64-unknown-linux-gnu-install_only.tar.gz"):
            continue
        ver = n.split("+")[0][len("cpython-"):]
        if ".".join(ver.split(".")[:2]) == minor and (best is None or vkey(ver) > vkey(best)):
            best = ver
    return best


def newest_go(minor):
    best = None
    for r in http_json("https://go.dev/dl/?mode=json&include=all"):
        v = r["version"].removeprefix("go")
        if ".".join(v.split(".")[:2]) == minor and (best is None or vkey(v) > vkey(best)):
            best = v
    return best


def newest_java(feature):
    assets = http_json(
        "https://api.adoptium.net/v3/assets/latest/"
        f"{feature}/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse")
    if not assets:
        return None
    # semver is "21.0.12+101.0.LTS"; the binary endpoint wants "21.0.12+101",
    # which is also the form matrix.yml pins.
    semver = assets[0]["version"]["semver"].split(".LTS")[0]
    main, _, build = semver.partition("+")
    build = build.split(".")[0]
    return f"{main}+{build}" if build else main


# --- mapping a pinned version to the line it tracks -----------------------

def track(e):
    """Which upstream line should this entry follow, for its tool."""
    tool, v = e["tool"], e["version"]
    parts = v.split(".")
    if tool == "node":
        return parts[0]
    if tool == "python":
        return f"{parts[0]}.{parts[1]}"
    if tool == "go":
        return f"{parts[0]}.{parts[1]}"
    if tool == "java":
        return parts[0]
    return None


def artifact_for(tool, version, components=None):
    # "+" is not safe in an asset name; components are appended with "-".
    stem = f"{tool}-{version.replace('+', '-')}"
    for c in components or []:
        stem += f"-{c}"
    return f"{stem}-debian-trixie-amd64.tar.xz"


def find_bumps():
    bumps = []
    for e in matrixlib.load(str(MATRIX)):
        line = track(e)
        if line is None:
            print(f"skip {e['dir']}: no version feed for tool '{e['tool']}'",
                  file=sys.stderr)
            continue
        if e["components"]:
            # An entry with components (e.g. a rust cross-compile std) follows
            # its host toolchain's version; bumping it independently would
            # desync the pair, so it is bumped only via its host entry.
            continue
        try:
            latest = {"node": newest_node, "python": newest_python,
                      "go": newest_go, "java": newest_java}[e["tool"]](line)
        except Exception as ex:                     # noqa: BLE001
            print(f"warn {e['dir']}: feed unavailable ({ex})", file=sys.stderr)
            continue
        if not latest:
            print(f"warn {e['dir']}: no upstream release for {e['tool']} {line}",
                  file=sys.stderr)
            continue
        if latest != e["version"]:
            bumps.append({"dir": e["dir"], "tool": e["tool"],
                          "from": e["version"], "to": latest,
                          "artifact": artifact_for(e["tool"], latest)})
    return bumps


def apply_bumps(bumps):
    """Rewrite version/artifact/sha256 for each bumped entry.

    Line-range editing, not a multi-line regex: the boundaries of each `- tool:`
    block are known, and a lazy regex across fields is what either over-matched
    a sibling or failed to match at all in the previous implementation.
    """
    text = MATRIX.read_text()
    lines = text.splitlines()

    # Walk the list and record each block's [start, end] line span, plus the
    # fields needed to rebuild its directory name.
    blocks = []
    cur = None
    for i, line in enumerate(lines):
        if re.match(r"^  - ", line):
            if cur:
                cur["end"] = i - 1
            cur = {"start": i, "end": len(lines) - 1, "tool": None,
                   "version": None, "components": []}
            blocks.append(cur)
            m = re.match(r"^  - tool:\s*(\S+)", line)
            if m:
                cur["tool"] = m.group(1)
            continue
        if cur and re.match(r"^\s+version:", line):
            cur["version"] = re.search(r'"([^"]*)"', line).group(1)
        if cur and re.match(r"^\s+components:", line):
            # Inline form `components: [a, b]`; the block form is handled below.
            m = re.search(r"\[([^\]]*)\]", line)
            if m:
                cur["components"] = [x.strip().strip('"')
                                     for x in m.group(1).split(",") if x.strip()]
        if cur and re.match(r"^\s+- ", line) and cur.get("components") is not None:
            # Block form continuation (6-space `- item` under `components:`).
            cur["components"].append(line.strip()[2:].strip().strip('"'))
    if cur:
        cur["end"] = len(lines) - 1

    # index by the derived directory name, components included
    index = {}
    for b in blocks:
        if b["tool"] and b["version"]:
            d = f'{b["tool"]}-{b["version"]}'
            for c in b["components"]:
                d += f'+{c}'
            index[d] = b

    def field_line(b, field):
        for i in range(b["start"], b["end"] + 1):
            if re.match(rf"^\s+{field}:", lines[i]):
                return i
        return None

    for bump in sorted(bumps, key=lambda x: index[x["dir"]]["start"], reverse=True):
        b = index.get(bump["dir"])
        if b is None:
            print(f"FAIL {bump['dir']}: not found in matrix.yml", file=sys.stderr)
            return False
        vi = field_line(b, "version")
        ai = field_line(b, "artifact")
        si = field_line(b, "sha256")
        if vi is None or ai is None or si is None:
            print(f"FAIL {bump['dir']}: block lacks version/artifact/sha256 "
                  f"(matrix.yml layout changed?)", file=sys.stderr)
            return False
        lines[vi] = re.sub(r'("[^"]*"|\S+)\s*$', f'"{bump["to"]}"', lines[vi], count=1)
        lines[ai] = re.sub(r'("[^"]*"|\S+)\s*$', f'"{bump["artifact"]}"', lines[ai], count=1)
        lines[si] = re.sub(r'("[^"]*")\s*$', '""', lines[si], count=1)

    MATRIX.write_text("\n".join(lines) + "\n")
    return True


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true")
    g.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    bumps = find_bumps()
    if not bumps:
        print("bump: every pin is current")
        return 0
    for b in bumps:
        print(f'{b["dir"]:24} {b["from"]:>14} -> {b["to"]}')
    if args.check:
        print(f"\nbump: {len(bumps)} stale pin(s)")
        return 1
    if not apply_bumps(bumps):
        return 2
    print(f"\nbump: rewrote {len(bumps)} pin(s) "
          f"(sha256 cleared; the release workflow re-pins)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
