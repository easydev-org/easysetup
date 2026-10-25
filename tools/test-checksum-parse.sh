#!/bin/bash
# Exercise the .sha256 parsing in action.yml against every shape it can meet.
#
# The parsing is the kind of code that looks obviously right and is not: the
# previous version used `sed -n '1s/[[:space:]].*//p'`, whose p flag prints only
# when the substitution matched - so a bare digest, which has no whitespace,
# printed nothing. Every install failed with "published checksum is empty" and the
# release looked broken. These cases pin the behaviour down.
set -uo pipefail

H=04acdaecef77ba4af0a72765bb09084aa195ae31aedd6fb68b6d91a5812bf27e
pass=0
fail=0

# The exact expression from action.yml.
extract() {
  printf '%s' "$(tr -d '[:space:]' < "$1")" | cut -c1-64
}

check() {
  local label="$1" file="$2" expect="$3"
  local got
  got=$(extract "$file")
  local verdict
  if [ -z "$got" ]; then verdict="REJECT:empty"
  elif [ "${#got}" -ne 64 ]; then verdict="REJECT:len=${#got}"
  elif [ -n "$(printf '%s' "$got" | tr -d '0123456789abcdefABCDEF')" ]; then
    verdict="REJECT:not-hex"
  # Case-insensitive: hex digests are the same number either way, and easysetup's
  # own comparison uses strings.EqualFold. A case-sensitive test here would reject
  # a file the real code accepts, and the test would be the thing that was wrong.
  elif [ "$(printf '%s' "$got" | tr 'A-F' 'a-f')" = "$H" ]; then verdict="ACCEPT"
  else verdict="REJECT:mismatch"; fi

  if [ "$verdict" = "$expect" ]; then
    printf '  ok    %-22s %s\n' "$label" "$verdict"; pass=$((pass+1))
  else
    printf '  FAIL  %-22s %s (wanted %s)\n' "$label" "$verdict" "$expect"; fail=$((fail+1))
  fi
}

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

printf '%s\n' "$H"            > "$t/bare"      # what easysetup-cli publishes
printf '%s  easysetup\n' "$H" > "$t/coreutils" # what sha256sum writes
: >                             "$t/empty"
printf 'zzzz%s\n' "$H"        > "$t/nothex"
printf '%s\n' "${H:0:32}"     > "$t/short"
printf '%s\n' "$(printf '%s' "$H" | tr 'a-f' 'A-F')" > "$t/upper"
printf '  %s  \n' "$H"        > "$t/spaced"

echo "== .sha256 parsing =="
check "bare digest"      "$t/bare"      ACCEPT
check "coreutils form"   "$t/coreutils" ACCEPT
check "uppercase hex"    "$t/upper"     ACCEPT
check "surrounding ws"   "$t/spaced"    ACCEPT
check "empty file"       "$t/empty"     "REJECT:empty"
check "non-hex"          "$t/nothex"    "REJECT:not-hex"
check "truncated"        "$t/short"     "REJECT:len=32"

echo

# The test above reimplements the expression, which means it can drift from the
# real one: change action.yml and this file keeps passing while the action breaks.
# That is the same class of failure as the original bug - two places agreeing with
# each other and disagreeing with reality - so the expression is compared against
# action.yml here.
echo "== the expression still matches action.yml =="
ACTION="$(dirname "$0")/../action.yml"
if [ ! -f "$ACTION" ]; then
  echo "  SKIP  action.yml not found (running outside the repo?)"
else
  if grep -q "tr -d '\[:space:\]' < \"\$bin.sha256\"" "$ACTION" &&
     grep -q 'cut -c1-64' "$ACTION"; then
    echo "  ok    action.yml uses the same tr + cut form"; pass=$((pass+1))
  else
    echo "  FAIL  action.yml no longer uses 'tr -d [:space:]' + 'cut -c1-64'"
    echo "        update this test alongside it, or the two have diverged"
    fail=$((fail+1))
  fi
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
