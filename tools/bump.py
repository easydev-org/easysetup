#!/usr/bin/env python3
"""bump.py — find setups in matrix.yml whose pin is behind upstream.

    bump.py --check     print stale entries, exit 1 if any (for CI)
    bump.py --apply     rewrite matrix.yml in place with the new pins

Each setup id tracks ONE upstream release line, derived from its own name:

    node-22     -> the newest 22.x
    python-312  -> the newest 3.12.x
    go-124      -> the newest 1.24.x
    java-17     -> the newest 17 GA

So several ids for one tool (node-22 / node-24 / node-26) each keep their own
line and none of them "wins" over another. A bump also REWRITES the artifact
name, because the asset name carries the version, and clears the sha256 so the
release workflow re-pins it after it builds the new asset.

Nothing here touches the network except the four version feeds.
"""

import argparse
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
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


# ---------------------------------------------------------------- upstream ---

def newest_node(major):
    """Newest published node for a major line, e.g. 22 -> 22.23.4."""
    for rel in http_json("https://nodejs.org/dist/index.json"):
        v = rel["version"].lstrip("v")
        # Only consider builds that actually ship a linux-x64 tarball, since
        # that is what build-node.sh downloads.
        if v.split(".")[0] == major and "linux-x64" in rel.get("files", []):
            return v
    return None


def newest_python(minor):
    """Newest install_only CPython for a minor line, e.g. 3.12 -> 3.12.15."""
    rel = http_json("https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest")
    best = None
    for a in rel["assets"]:
        n = a["name"]
        if not n.startswith("cpython-"):
            continue
        if not n.endswith("-x86_64-unknown-linux-gnu-install_only.tar.gz"):
            continue
        ver = n.split("+")[0][len("cpython-"):]
        if ".".join(ver.split(".")[:2]) == minor:
            if best is None or _vkey(ver) > _vkey(best):
                best = ver
    return best


def newest_go(minor):
    """Newest go for a minor line, e.g. 1.24 -> 1.24.13."""
    best = None
    for r in http_json("https://go.dev/dl/?mode=json&include=all"):
        v = r["version"].removeprefix("go")
        if ".".join(v.split(".")[:2]) == minor:
            if best is None or _vkey(v) > _vkey(best):
                best = v
    return best


def newest_java(feature):
    """Newest Temurin GA for a feature release, e.g. 21 -> 21.0.12+101."""
    assets = http_json(
        "https://api.adoptium.net/v3/assets/latest/"
        f"{feature}/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse")
    if not assets:
        return None
    # semver looks like "21.0.12+101.0.LTS". The binary endpoint accepts the
    # build number only ("21.0.12+101"), and that is the form matrix.yml pins -
    # so drop the ".LTS" tag AND the trailing ".0" on the build, otherwise the
    # comparison reports a permanent phantom bump of "+101" vs "+101.0".
    semver = assets[0]["version"]["semver"].split(".LTS")[0]
    main, _, build = semver.partition("+")
    build = build.split(".")[0]
    return f"{main}+{build}" if build else main


def _vkey(v):
    """Sort key for dotted versions with an optional +build suffix."""
    main, _, build = v.partition("+")
    nums = [int(x) for x in re.findall(r"\d+", main)]
    bnums = [int(x) for x in re.findall(r"\d+", build)]
    return (nums, bnums)


# ------------------------------------------------------------------ matrix ---

def read_matrix():
    """Parse matrix.yml into an ordered list of (id, fields, line span)."""
    text = MATRIX.read_text()
    entries = []
    cur = None
    for i, line in enumerate(text.splitlines()):
        m = re.match(r"^  ([a-z0-9-]+):$", line)
        if m:
            cur = {"id": m.group(1), "start": i, "end": i, "fields": {}}
            entries.append(cur)
            continue
        if cur is None:
            continue
        cur["end"] = i
        for f in ("tool", "version", "artifact", "sha256"):
            # Quotes are OPTIONAL in matrix.yml (`tool: node` is unquoted,
            # `version: "22.23.4"` is quoted). Requiring them silently read no
            # fields at all and every setup looked like it had no version.
            m2 = re.match(rf'^\s+{f}:\s*"?([^"#\s]*)"?\s*(?:#.*)?$', line)
            if m2:
                cur["fields"][f] = m2.group(1)
    return text, entries


def track_of(sid, tool):
    """node-22 -> '22'; python-312 -> '3.12'; go-124 -> '1.24'; java-17 -> '17'."""
    suffix = sid[len(tool) + 1:]
    if tool == "python":
        return f"{suffix[0]}.{suffix[1:]}"
    if tool == "go":
        return f"{suffix[0]}.{suffix[1:]}"
    return suffix


def artifact_for(tool, version):
    if tool == "java":
        # "+" is not valid in an asset name.
        return f"java-{version.replace('+', '-')}-debian-trixie-amd64.tar.xz"
    return f"{tool}-{version}-debian-trixie-amd64.tar.xz"


def find_bumps():
    _, entries = read_matrix()
    bumps = []
    for e in entries:
        tool = e["fields"].get("tool")
        pinned = e["fields"].get("version")
        if not tool or not pinned:
            print(f"skip {e['id']}: no tool/version", file=sys.stderr)
            continue
        track = track_of(e["id"], tool)
        try:
            if tool == "node":
                latest = newest_node(track)
            elif tool == "python":
                latest = newest_python(track)
            elif tool == "go":
                latest = newest_go(track)
            elif tool == "java":
                latest = newest_java(track)
            else:
                print(f"skip {e['id']}: unknown tool {tool}", file=sys.stderr)
                continue
        except Exception as ex:                     # noqa: BLE001
            print(f"warn {e['id']}: feed unavailable ({ex})", file=sys.stderr)
            continue
        if not latest:
            print(f"warn {e['id']}: no upstream release for {tool} {track}", file=sys.stderr)
            continue
        if latest != pinned:
            bumps.append({"id": e["id"], "tool": tool,
                          "from": pinned, "to": latest,
                          "artifact": artifact_for(tool, latest)})
    return bumps


def apply_bumps(bumps):
    text, _ = read_matrix()
    lines = text.splitlines()

    # Edit by LINE RANGE, not by a multi-line regex. A regex spanning several
    # fields has to express "somewhere in this block" with lazy quantifiers,
    # which is exactly the kind of pattern that either over-matches a sibling id
    # or fails to match at all. The block boundaries are already known from
    # read_matrix, so use them.
    #
    # Work bottom-up so earlier line numbers stay valid as we splice.
    _, entries = read_matrix()
    by_id = {e["id"]: e for e in entries}

    def field_line(idx_from, idx_to, field):
        for i in range(idx_from, min(idx_to + 1, len(lines))):
            if re.match(rf"^\s+{field}:", lines[i]):
                return i
        return None

    for b in sorted(bumps, key=lambda x: by_id[x["id"]]["start"], reverse=True):
        e = by_id.get(b["id"])
        if e is None:
            print(f"FAIL {b['id']}: not in matrix.yml", file=sys.stderr)
            return False
        vi = field_line(e["start"], e["end"], "version")
        ai = field_line(e["start"], e["end"], "artifact")
        si = field_line(e["start"], e["end"], "sha256")
        if vi is None or ai is None or si is None:
            print(f"FAIL {b['id']}: expected version/artifact/sha256 lines in "
                  f"this block (matrix.yml layout changed?)", file=sys.stderr)
            return False
        # Keep each line's indentation; only replace the value.
        lines[vi] = re.sub(r'("[^"]*"|\S+)\s*$', f'"{b["to"]}"', lines[vi], count=1)
        lines[ai] = re.sub(r'("[^"]*"|\S+)\s*$', f'"{b["artifact"]}"', lines[ai], count=1)
        # The asset name changed, so the old digest cannot match: clear it and
        # let the release workflow re-pin after it builds the new asset.
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
        print(f"{b['id']:12} {b['from']:>14} -> {b['to']}")

    if args.check:
        print(f"\nbump: {len(bumps)} stale pin(s)")
        return 1

    if not apply_bumps(bumps):
        return 2
    print(f"\nbump: rewrote {len(bumps)} pin(s) in matrix.yml "
          f"(sha256 cleared; the release workflow will re-pin)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
