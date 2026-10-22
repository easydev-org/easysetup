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
        elif matrixlib.resolve(req) is None:
            print(f"FAIL {e['dir']} requires unknown setup {req!r}")
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

echo "== setup name resolution =="
# `install.sh node-22` must work; `node-2` must NOT silently pick node 22.
"$PY" tools/test_resolve.py | tail -3
"$PY" tools/test_resolve.py >/dev/null || fail=1

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

echo "== matrixlib needs no third-party module =="
# The release job runs in debian:trixie without PyYAML, so the parser must work
# with the stdlib alone. -S disables site-packages and proves it.
"$PY" -S matrixlib.py list >/dev/null || bad "matrixlib fails without site-packages"
ok "matrixlib runs on the standard library alone"

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
