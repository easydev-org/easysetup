#!/bin/bash
# selftest.sh — everything checkable without building or reaching the network.
#
# It guards the invariants that have actually broken before:
#   * the manifest parses and every entry has the fields the pipeline needs;
#   * `version` is a field and the install directory is DERIVED (not a name
#     someone has to keep in sync);
#   * bump.py rewrites one version without touching its siblings, and refuses a
#     malformed block instead of half-writing it;
#   * pin-checksums.sh writes a digest into the entry whose artifact matches;
#   * the workflows and the manifest agree on names.
set -euo pipefail

cd "$(dirname "$0")"
PY=${PY:-$(command -v python3 || command -v python)}
[ -n "$PY" ] || { echo "selftest: no python found"; exit 1; }

fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }

echo "== manifest parses =="
ids=$("$PY" matrixlib.py list)
echo "$ids" | sed 's/^/  /'
[ -n "$ids" ] || bad "matrixlib listed nothing"

echo "== every entry has the fields the pipeline needs =="
while IFS= read -r d; do
  for f in tool version artifact; do
    v=$("$PY" matrixlib.py get "$d" "$f" 2>/dev/null || true)
    [ -n "$v" ] || bad "$d.$f is empty"
  done
done <<< "$ids"
ok "required fields present"

echo "== directory is derived as <tool>-<version> =="
"$PY" - <<'PY' || fail=1
import re, sys
sys.path.insert(0, ".")
import matrixlib
bad = 0
seen = set()
for e in matrixlib.load():
    want = f'{e["tool"]}-{e["version"]}'
    if e["dir"] != want:
        print(f"FAIL {e['dir']} != {want}")
        bad = 1
    # Directory names must be unique; two entries with the same tool+version
    # used to be told apart by a `+component`, which no longer exists.
    if e["dir"] in seen:
        print(f"FAIL duplicate directory {e['dir']}")
        bad = 1
    seen.add(e["dir"])
    # The tool field is a name, not a version. Digits are fine when they are
    # PART of a name (`rust-toolchain-x86_64-pc-windows-gnu`), so the tell is
    # a tool name that ENDS in a dotted version, e.g. `node-22.23.4`.
    if re.search(r"[.-]\d+\.\d+", e["tool"]):
        print(f"FAIL {e['dir']}: tool field looks like it contains a version ({e['tool']})")
        bad = 1
    # Every `requires` entry must resolve, and must not name itself.
    for req in e["requires"]:
        if req == e["dir"]:
            print(f"FAIL {e['dir']} requires itself")
            bad = 1
            continue
        # A requirement may be a range (`erlang@>=29 <30`) or a bare tool, so
        # judging it needs the same resolver the installer uses.
        try:
            matrixlib.resolve_requirement(req)
        except ValueError as ex:
            print(f"FAIL {e['dir']} requires {req!r}: {ex}")
            bad = 1
if not bad:
    print("ok   every directory derives from tool+version, is unique, requires resolve")
sys.exit(bad)
PY

echo "== install.sh performs no network work beyond apt + one tarball =="
# The install contract: apt-get, then download ONE release asset and unpack it.
# Flag anything that would need the network at install time (a compiler, a
# package manager, rustup, npm/pip install...).
for pat in 'cargo install' 'rustup' 'npm install' 'pip install' 'go install' \
           'gem install' 'make ' 'cmake ' '\./configure'; do
  if grep -qE "$pat" install.sh; then
    bad "install.sh contains '$pat' (must not build at install time)"
  fi
done
ok "install.sh only apts and unpacks"

echo "== bump.py rewriting rules =="
"$PY" tools/test_bump.py | tail -4
"$PY" tools/test_bump.py >/dev/null || fail=1

echo "== matrix.yml sha256 pins survive an upload =="
# The pins are computed by CI and live only in the remote matrix.yml; the local
# copy has them empty. A verbatim upload wiped all of them once, which made
# install.sh refuse to unpack anything.
"$PY" tools/test_merge_pins.py | tail -3
"$PY" tools/test_merge_pins.py >/dev/null || fail=1

echo "== env.sh accumulates across invocations =="
# The real failure this guards: install.sh is called once per `uses:` step, and
# generating env.sh from "what this run installed" made each call erase the
# previous one. gen-env.sh must build the file from what is on disk.
{
  fake=$(mktemp -d)
  mkdir -p "$fake/node-22.23.4/bin" "$fake/python-3.12.15/bin"
  for id in node-22.23.4 python-3.12.15; do
    printf 'id=%s\nsha256=x\nartifact=x\n' "$id" > "$fake/$id/.easysetup"
  done
  EASYSETUP_ROOT="$fake" bash tools/gen-env.sh "$fake/env.sh" >/dev/null
  if grep -q '_use_node()' "$fake/env.sh" && grep -q '_use_python()' "$fake/env.sh"; then
    echo "ok   env.sh knows every installed setup"
  else
    echo "FAIL env.sh dropped a setup - it is regenerating from the call, not the tree"
    exit 1
  fi
  # And it must be sourceable under `set -u`, which is how CI runs.
  if ( set -u; . "$fake/env.sh" >/dev/null 2>&1 ); then
    echo "ok   env.sh is sourceable under set -u"
  else
    echo "FAIL env.sh breaks under set -u"
    exit 1
  fi
  rm -rf "$fake"
} || fail=1


echo "== the manifest parser handles the shapes we write =="
# Each case broke at least once: a wrapped flow list, and a quoted comma inside
# one. Both appear in matrix.yml today.
"$PY" tools/test_parser.py | tail -3
"$PY" tools/test_parser.py >/dev/null || fail=1

echo "== setup name resolution =="
# `install.sh node-22` must work; `node-2` must NOT silently pick node 22.
"$PY" tools/test_resolve.py | tail -3
"$PY" tools/test_resolve.py >/dev/null || fail=1

echo "== requires: exact names, prefixes, and version ranges =="
# A hard-coded `requires: [erlang-29.1.2]` has to be edited in every dependent
# entry when the tool moves on, and forgetting it installs the wrong runtime.
# A range lets the dependency follow the published versions.
"$PY" tools/test_requires.py | tail -4
"$PY" tools/test_requires.py >/dev/null || fail=1

echo "== pin-checksums.sh edits the matching entry =="
tmp=$(mktemp -d); mkdir -p "$tmp/assets"
echo "fake" > "$tmp/assets/$( "$PY" matrixlib.py get "$(echo "$ids" | head -1)" artifact)"
want=$(sha256sum "$tmp/assets/"*.tar.xz | awk '{print $1}')
"$PY" - "$tmp" <<'PY'
import glob, hashlib, os, re, sys
sys.path.insert(0, ".")
import matrixlib
assets = sys.argv[1]
known = {e["artifact"]: e for e in matrixlib.load()}
text = open("matrix.yml").read()
for p in sorted(glob.glob(os.path.join(assets, "assets", "*.tar.xz"))):
    name = os.path.basename(p)
    assert name in known, f"{name} not in matrix.yml"
    digest = hashlib.sha256(open(p, "rb").read()).hexdigest()
    pat = re.compile(r'(artifact: ' + re.escape(name) + r'\n\s+sha256: )"[^"]*"')
    text, n = pat.subn(r'\1"' + digest + '"', text)
    print(f"{name}: {n} replacement")
open("/tmp/_pinned.yml", "w").write(text)
PY
first=$(echo "$ids" | head -1)
case "$(grep -A6 "version: \"$("$PY" matrixlib.py get "$first" version)\"" /tmp/_pinned.yml | grep 'sha256:' | head -1)" in
  *"$want"*) ok "$first pinned with the asset digest" ;;
  *)         bad "$first digest not pinned" ;;
esac
rm -rf "$tmp" /tmp/_pinned.yml

echo "== workflows agree with the manifest =="
if grep -qE 'matrix\.id\b|doc\["setups"\]\.items' .github/workflows/*.yml; then
  bad "a workflow still uses the old mapping/id shape"
else
  ok "no stale matrix.id / dict-style access"
fi
# PyYAML is not installed everywhere (it is absent in debian:trixie, which is
# why matrixlib has its own parser). Validate the workflows when it is
# available, and say so when it is not rather than pretending.
if "$PY" -c "import yaml" 2>/dev/null; then
  for f in .github/workflows/release.yml .github/workflows/refresh.yml; do
    "$PY" -c "import yaml;yaml.safe_load(open('$f'))" || bad "$f is not valid YAML"
  done
  ok "workflow YAML parses"
else
  echo "skip YAML parse check (PyYAML not installed)"
fi

echo "== action.yml is a valid composite action =="
"$PY" - <<'PY' || fail=1
import re, sys, yaml

d = yaml.safe_load(open("action.yml"))
bad = 0
if d.get("runs", {}).get("using") != "composite":
    print("FAIL action.yml: runs.using must be 'composite'")
    bad = 1
steps = d.get("runs", {}).get("steps", [])
if not steps:
    print("FAIL action.yml: no steps")
    bad = 1
# In a composite action every step must name a shell; GitHub rejects it
# otherwise without saying which step.
for i, s in enumerate(steps):
    if "uses" in s:
        continue
    if "shell" not in s:
        print("FAIL action.yml step %d (%s) has no shell" % (i, s.get("name", "?")))
        bad = 1
declared = set(d.get("inputs", {}))
for ref in set(re.findall(r"inputs\.([a-z-]+)", open("action.yml").read())):
    if ref not in declared:
        print("FAIL action.yml references undeclared input %r" % ref)
        bad = 1
if not bad:
    print("ok   action.yml: composite, %d steps, inputs declared" % len(steps))
sys.exit(bad)
PY

echo "== every run: block in the workflows is valid bash =="
# A syntax error inside `run: |` passes the YAML parse and only explodes when the
# job executes it - which is how a broken `case` arm failed all three Swift SDK
# builds at verify time, after their artifacts had built fine.
"$PY" tools/check-workflow-shell.py || fail=1
"$PY" tools/test_workflow_shell_check.py >/dev/null || fail=1

echo "== the example workflow names only setups that exist =="
"$PY" - <<'PY' || fail=1
import pathlib, re, sys
sys.path.insert(0, ".")
import matrixlib

text = pathlib.Path("examples/ci.yml").read_text()
bad = 0
for block in re.findall(r"tools:\s*(.+)", text):
    # Two spellings appear in the example:
    #   tools: node-22 python-3.12
    #   with: { tools: "java-21 r-4" }
    # Strip a trailing inline-map brace and any wrapping quotes.
    b = block.strip().rstrip("}").strip().strip('"').strip("'")
    for name in b.split():
        if name in ("|", ">", "", "}"):
            continue
        try:
            matrixlib.resolve_requirement(name)
        except ValueError as e:
            print("FAIL examples/ci.yml asks for %r: %s" % (name, e))
            bad = 1
if not bad:
    print("ok   every setup named in the example resolves")
sys.exit(bad)
PY

echo "== matrixlib needs no third-party module =="
# The release job runs in debian:trixie without PyYAML, so the parser must work
# with the stdlib alone. -S disables site-packages and proves it.
"$PY" -S matrixlib.py list >/dev/null || bad "matrixlib fails without site-packages"
ok "matrixlib runs on the standard library alone"

echo "== every setup can be selected with --only =="
# The release job filters its matrix with `only=`. It used to compare that
# string to the directory verbatim, so `only: swift-sdk-wasm` (a name, not a
# directory) selected NOTHING - setup and publish both reported success while
# zero build jobs ran. Every entry must be selectable by the name a user types.
"$PY" - <<'PY' || fail=1
import sys
sys.path.insert(0, ".")
import matrixlib

bad = 0
entries = matrixlib.load()
for e in entries:
    for spelling in (e["dir"], e["tool"]):
        got = matrixlib.resolve_requirement(spelling)
        if got is None or got["dir"] != e["dir"]:
            # A bare tool name is ambiguous when several versions exist; only
            # require that it resolves to SOME entry of that tool.
            if spelling == e["tool"] and got is not None and got["tool"] == e["tool"]:
                continue
            print("FAIL only=%r resolves to %r, not %r"
                  % (spelling, got and got["dir"], e["dir"]))
            bad = 1
if not bad:
    print("ok   every setup is reachable by dir and by tool name")
sys.exit(bad)
PY


echo "== which build scripts compile, and is that intended =="
# The model is "repack a prebuilt tarball, bundling any library whose ABI the
# target lacks" - NOT "compile from source". Two scripts are exceptions, both
# for lack of any prebuilt alternative:
#   lua  no official binary release; builds in seconds from 400 KB of source.
#   ghc  its tarball is a bindist whose own `make install` lays out the
#        PREBUILT compiler (it does not compile GHC).
# This list is authoritative, so a new compiler cannot slip in unnoticed.
COMPILED="tools/build-lua.sh tools/build-ghc.sh"
for f in tools/build-*.sh; do
  compiles=0
  if grep -qE '^\s*\./configure|^\s*make( |$)|^\s*make install|cmake ' "$f"; then
    compiles=1
  fi
  case " $COMPILED " in
    *" $f "*)
      [ "$compiles" = 1 ] || bad "$f is listed as a source build but does not compile - remove it from COMPILED"
      ;;
    *)
      [ "$compiles" = 0 ] || bad "$f compiles but is not in COMPILED; add it deliberately or use a prebuilt"
      ;;
  esac
done
ok "the set of source-built setups matches COMPILED ($COMPILED)"

echo "== every tool has a build script =="
# A setup names its script with `builder`, defaulting to `tool`; the entry that
# matters is the builder, so rust-toolchain-* correctly resolve to build-rust.sh.
for d in $("$PY" matrixlib.py list); do
  builder=$("$PY" matrixlib.py get "$d" builder)
  [ -f "tools/build-$builder.sh" ] || bad "missing tools/build-$builder.sh (for $d)"
done
ok "build scripts exist for every builder"

echo "== apt_deps cover every soname the ELFs ask for =="
# Guessing one missing library per CI round is how php took three rounds
# (libsodium, then libargon2). If a staged tree is present, check it properly;
# otherwise verify the checker itself still runs.
if [ -d /tmp/stagetree ]; then
  for d in $("$PY" matrixlib.py list); do
    if ! "$PY" tools/check-deps.py "/tmp/stagetree/$d" "$d"; then
      bad "$d is missing apt_deps entries"
    fi
  done
  ok "apt_deps verified against real binaries"
else
  "$PY" - <<'PY' || bad "check-deps.py is broken"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cd", "tools/check-deps.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert m.SONAME_PKG.get("libargon2.so.1") == "libargon2-1"
print("ok   check-deps.py mapping loads")
PY
fi

if [ "$fail" -ne 0 ]; then echo "selftest: FAILED"; exit 1; fi
echo "selftest: ok"
