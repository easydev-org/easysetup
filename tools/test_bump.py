#!/usr/bin/env python3
"""test_bump.py — offline tests for the matrix format and bump's rewriting.

The refresh job edits matrix.yml unattended on a schedule, so the rules that
must not slip are pinned here:

  * `version` is a separate field; the directory is DERIVED as <tool>-<version>;
  * bumping one version leaves its siblings alone (node 22 vs node 24);
  * sha256 is cleared on bump (a different file cannot match the old digest);
  * a block that lacks version/artifact/sha256 fails the whole file rather
    than half-writing it.
"""

import importlib.util
import pathlib
import sys
import textwrap

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent

spec = importlib.util.spec_from_file_location("bump", HERE / "bump.py")
bump = importlib.util.module_from_spec(spec)
sys.path.insert(0, str(ROOT))
spec.loader.exec_module(bump)

MATRIX = textwrap.dedent("""\
    base:
      distro: debian-trixie

    setups:
      - tool: node
        version: "22.23.4"
        apt_deps: [ca-certificates, curl]
        artifact: node-22.23.4-debian-trixie-amd64.tar.xz
        sha256: "aaaa"

      - tool: node
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
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fail = 1


# --- the derived directory comes from fields, not from a name -------------
sys.path.insert(0, str(ROOT))
import matrixlib  # noqa: E402

entries = matrixlib.load(str(pathlib.Path("/tmp/_derived.yml"))) if False else None
tmp = pathlib.Path("/tmp/_derived.yml")
tmp.write_text(MATRIX)
derived = [e["dir"] for e in matrixlib.load(str(tmp))]
check("dir derived from tool+version", derived == ["node-22.23.4", "node-24.22.1"])
check("version is its own field",
      matrixlib.load(str(tmp))[0]["version"] == "22.23.4")

# --- bumping node 22 must not disturb node 24 ----------------------------
ok, out = run([{"dir": "node-22.23.4", "tool": "node", "from": "22.23.4",
                "to": "22.99.0",
                "artifact": "node-22.99.0-debian-trixie-amd64.tar.xz"}])
check("apply returns True", ok)
check("node 22 version bumped", 'version: "22.99.0"' in out)
check("node 22 artifact bumped", "node-22.99.0-debian-trixie-amd64.tar.xz" in out)
check("node 22 sha256 cleared", 'sha256: ""' in out)
check("node 24 version untouched", 'version: "24.22.1"' in out)
check("node 24 sha256 untouched", 'sha256: "bbbb"' in out)
check("old node 22 artifact gone", "node-22.23.4-debian-trixie" not in out)

# --- both at once ---------------------------------------------------------
ok, out = run([
    {"dir": "node-22.23.4", "tool": "node", "from": "22.23.4", "to": "22.99.0",
     "artifact": "node-22.99.0-debian-trixie-amd64.tar.xz"},
    {"dir": "node-24.22.1", "tool": "node", "from": "24.22.1", "to": "24.99.0",
     "artifact": "node-24.99.0-debian-trixie-amd64.tar.xz"},
])
check("both bumped",
      ok and 'version: "22.99.0"' in out and 'version: "24.99.0"' in out)
check("no cross-contamination", out.count('sha256: ""') == 2)

# --- artifact naming ------------------------------------------------------
check("java artifact replaces +",
      bump.artifact_for("java", "21.0.12+101")
      == "java-21.0.12-101-debian-trixie-amd64.tar.xz")
check("node artifact keeps version",
      bump.artifact_for("node", "22.23.4")
      == "node-22.23.4-debian-trixie-amd64.tar.xz")
check("rust target in artifact name",
      bump.artifact_for("rust", "1.99.1", "x86_64-pc-windows-gnu")
      == "rust-1.99.1-x86_64-pc-windows-gnu-debian-trixie-amd64.tar.xz")

# --- tracked line derivation ---------------------------------------------
check("track node", bump.track({"tool": "node", "version": "22.23.4"}) == "22")
check("track python", bump.track({"tool": "python", "version": "3.12.15"}) == "3.12")
check("track go", bump.track({"tool": "go", "version": "1.24.13"}) == "1.24")
check("track java", bump.track({"tool": "java", "version": "21.0.12+101"}) == "21")

# --- a block bump cannot rewrite must fail, not half-write ----------------
broken = "\n".join(l for l in MATRIX.splitlines() if l.strip() != 'sha256: "aaaa"')
check("fixture is really broken", 'sha256: "aaaa"' not in broken)
ok, out = run([{"dir": "node-22.23.4", "tool": "node", "from": "22.23.4",
                "to": "22.99.0",
                "artifact": "node-22.99.0-debian-trixie-amd64.tar.xz"}], broken)
check("incomplete block returns False", ok is False)
check("incomplete block writes nothing", "22.99.0" not in out)
check("incomplete block leaves node 24 alone", 'version: "24.22.1"' in out)

print(f"\ntest_bump: {'FAILED' if fail else 'ok'}")
raise SystemExit(1 if fail else 0)
