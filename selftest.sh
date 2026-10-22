#!/bin/bash
# selftest.sh — check the installer's manifest parsing against the REAL
# matrix.yml, without network access to the releases.
#
# The parse is the part that silently breaks: an id that the awk section regex
# does not match makes every lookup return empty, and the failure then looks
# like "the setup does not exist" rather than "the parser is wrong".
set -euo pipefail

cd "$(dirname "$0")"
MANIFEST=matrix.yml

manifest_get() {
  awk -v want="$1" -v field="$2" '
    /^  [a-z0-9-]+:$/ { name=$1; sub(":","",name); next }
    name==want && $1==field":" { sub(/^[^:]*:[ ]*/,""); gsub(/"/,""); print; exit }
  ' "$MANIFEST"
}

manifest_ids() {
  awk '/^  [a-z0-9-]+:$/ { n=$1; sub(":","",n); print n }' "$MANIFEST"
}

fail=0
check() {  # check <id> <field> <expected-prefix>
  got=$(manifest_get "$1" "$2")
  case "$got" in
    "$3"*) ;;
    *) echo "FAIL $1.$2: got [$got], want prefix [$3]"; fail=1 ;;
  esac
}

echo "== ids =="
for id in $(manifest_ids); do echo "  $id"; done

echo "== required fields =="
for id in $(manifest_ids); do
  for f in tool version artifact; do
    v=$(manifest_get "$id" "$f")
    [ -n "$v" ] || { echo "FAIL $id.$f is empty"; fail=1; }
  done
done

echo "== spot checks =="
check node-22     tool     node
check node-22     version  22.
check node-26     version  26.
check python-315  version  3.15.
check go-124      version  1.24.
check go-127      version  1.27.
check java-27     version  27.
check java-21     artifact java-21.

echo "== every apt_deps parses =="
for id in $(manifest_ids); do
  d=$(awk -v want="$id" '
    /^  [a-z0-9-]+:$/ { name=$1; sub(":","",name); next }
    name==want && /apt_deps:/ { sub(/^[^[]*\[/,""); sub(/\].*/,""); gsub(/,/," "); print; exit }
  ' "$MANIFEST")
  [ -n "$d" ] || { echo "FAIL $id: apt_deps did not parse"; fail=1; }
done

echo "== workflow references match the manifest shape =="
# The release workflow builds its matrix from matrix.yml and then refers to the
# fields by name. Renaming a key there and forgetting one reference produced a
# KeyError that only showed up as a failed `setup` job. Check the two agree.
#
# PY points at whatever python has PyYAML; the CI image guarantees python3, a
# developer machine may only have python.
PY=${PY:-$(command -v python3 || command -v python)}
[ -n "$PY" ] || { echo "selftest: no python found"; exit 1; }
"$PY" - <<'PY'
import re, sys, yaml

doc = yaml.safe_load(open("matrix.yml"))
ids = list(doc["setups"])
sample = doc["setups"][ids[0]]

wf = open(".github/workflows/release.yml").read()

# 1. every setup must carry the fields the workflow reads.
for i, s in doc["setups"].items():
    for f in ("tool", "version", "artifact"):
        if f not in s:
            sys.exit(f"selftest: setup {i} is missing '{f}'")

# 2. keys the workflow expects from the generated matrix include-list.
for key in ('"id"', '"tool"', '"version"', '"artifact"'):
    if key not in wf:
        sys.exit(f"selftest: release.yml never mentions {key}")

# 3. no stale reference to the old key name.
if re.search(r'x\["name"\]|matrix\.name\b', wf):
    sys.exit("selftest: release.yml still refers to the old 'name' key")

print("selftest: workflow keys agree with the manifest")
PY

if [ "$fail" -ne 0 ]; then echo "selftest: FAILED"; exit 1; fi
echo "selftest: ok"
