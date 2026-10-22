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

if [ "$fail" -ne 0 ]; then echo "selftest: FAILED"; exit 1; fi
echo "selftest: ok"
