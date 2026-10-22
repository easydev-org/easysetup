#!/usr/bin/env python3
"""test_bump.py — check bump.py's rewriting rules without any network access.

The dangerous part of the refresh job is the EDIT: it runs unattended on a
schedule, so a regex that matches too much would silently rewrite a setup nobody
meant to touch. These cases pin the behaviour that matters:

  * only the bumped id's version/artifact/sha256 change;
  * a sibling id for the same tool is untouched;
  * sha256 is cleared (the asset name changed, so the old digest cannot match);
  * a matrix where the block layout differs fails loudly instead of half-writing.
"""

import importlib.util
import pathlib
import textwrap

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("bump", HERE / "bump.py")
bump = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bump)

MATRIX = textwrap.dedent("""\
    base:
      distro: debian-trixie

    setups:
      node-22:
        tool: node
        version: "22.23.4"
        apt_deps: [ca-certificates, curl]
        artifact: node-22.23.4-debian-trixie-amd64.tar.xz
        sha256: "aaaa"

      node-24:
        tool: node
        version: "24.22.1"
        apt_deps: [ca-certificates, curl]
        artifact: node-24.22.1-debian-trixie-amd64.tar.xz
        sha256: "bbbb"
    """)


def run(bumps, matrix=MATRIX):
    tmp = pathlib.Path("/tmp/_test_matrix.yml")
    tmp.write_text(matrix)
    orig = bump.MATRIX
    bump.MATRIX = tmp
    try:
        ok = bump.apply_bumps(bumps)
        return ok, tmp.read_text()
    finally:
        bump.MATRIX = orig


fail = 0


def check(name, cond):
    global fail
    if cond:
        print(f"ok   {name}")
    else:
        print(f"FAIL {name}")
        fail = 1


# --- bumping node-22 must not disturb node-24 -----------------------------
ok, out = run([{"id": "node-22", "tool": "node", "from": "22.23.4",
                "to": "22.99.0",
                "artifact": "node-22.99.0-debian-trixie-amd64.tar.xz"}])
check("apply returns True", ok)
check("node-22 version bumped", 'version: "22.99.0"' in out)
check("node-22 artifact bumped", "node-22.99.0-debian-trixie-amd64.tar.xz" in out)
check("node-22 sha256 cleared", 'sha256: ""' in out)
check("node-24 version untouched", 'version: "24.22.1"' in out)
check("node-24 sha256 untouched", 'sha256: "bbbb"' in out)
check("old node-22 artifact gone", "node-22.23.4-debian-trixie" not in out)

# --- two absolutely identical ids (same tool, different line) --------------
ok, out = run([
    {"id": "node-22", "tool": "node", "from": "22.23.4", "to": "22.99.0",
     "artifact": "node-22.99.0-debian-trixie-amd64.tar.xz"},
    {"id": "node-24", "tool": "node", "from": "24.22.1", "to": "24.99.0",
     "artifact": "node-24.99.0-debian-trixie-amd64.tar.xz"},
])
check("both bumped", ok and 'version: "22.99.0"' in out and 'version: "24.99.0"' in out)
check("no cross-contamination", out.count('sha256: ""') == 2)

# --- java's +build must survive into a filename safely --------------------
check("java artifact replaces +", bump.artifact_for("java", "21.0.12+101")
      == "java-21.0.12-101-debian-trixie-amd64.tar.xz")
check("node artifact keeps version", bump.artifact_for("node", "22.23.4")
      == "node-22.23.4-debian-trixie-amd64.tar.xz")

# --- track derivation ------------------------------------------------------
check("track node-22", bump.track_of("node-22", "node") == "22")
check("track python-312", bump.track_of("python-312", "python") == "3.12")
check("track go-124", bump.track_of("go-124", "go") == "1.24")
check("track java-27", bump.track_of("java-27", "java") == "27")

# --- a layout bump.py cannot rewrite must fail, not half-write ------------
#
# Drop the sha256 line from node-22 only. The block no longer has the three
# fields the rewrite needs, so bump must refuse the WHOLE file rather than
# updating version/artifact and leaving the checksum stale.
# Build it by dropping the line, so indentation in this test file cannot make
# the replacement silently miss (it did: the fixture was never actually broken,
# which made the two assertions below pass vacuously).
broken = "\n".join(l for l in MATRIX.splitlines() if l.strip() != 'sha256: "aaaa"')
check("test fixture is really broken", 'sha256: "aaaa"' not in broken)

ok, out = run([{"id": "node-22", "tool": "node", "from": "22.23.4",
                "to": "22.99.0",
                "artifact": "node-22.99.0-debian-trixie-amd64.tar.xz"}], broken)
check("unmatched layout returns False", ok is False)
check("unmatched layout writes nothing", "22.99.0" not in out)
check("unmatched layout left node-24 alone", 'version: "24.22.1"' in out)

print(f"\ntest_bump: {'FAILED' if fail else 'ok'}")
raise SystemExit(1 if fail else 0)
