#!/bin/bash
# Measure the real overlap between published tarballs.
#
# The design question: each tarball carries a complete closure, so a job asking
# for several tools downloads shared libraries (glibc above all) once per
# tarball. How much would a shared-base scheme actually save?
#
# This answers it from the ARTIFACTS THEMSELVES, not from theory: download what
# is published, unpack each into its own root, and compare the store paths. That
# is the same bytes a consumer receives.
set -uo pipefail

REPO="${EASYSETUP_REPO:-easydev-org/easysetup}"
BASE="https://github.com/${REPO}/releases/download"
W=/data/delta
rm -rf "$W"; mkdir -p "$W"

# A spread of sizes and ecosystems, all actually published.
SETUPS="jq-1.8.2 yq-4.54.1 node-26.12.0 python-3.15.0 php-8.5.11 cmake-4.4.4"

echo "== downloading published artifacts =="
for d in $SETUPS; do
  a="$d-debian-trixie-amd64.tar.zst"
  if [ ! -f "$W/$a" ]; then
    curl -fsSL --retry 3 --max-time 600 -o "$W/$a" "$BASE/$d/$a" || {
      echo "  FAILED $d" >&2; continue; }
  fi
  printf '  %-26s %s\n' "$d" "$(du -h "$W/$a" | cut -f1)"
done

echo
echo "== unpacking each into its own root =="
for d in $SETUPS; do
  a="$d-debian-trixie-amd64.tar.zst"
  [ -f "$W/$a" ] || continue
  mkdir -p "$W/x/$d"
  zstd -d --quiet -c "$W/$a" | tar -xf - -C "$W/x/$d"
  n=$(ls "$W/x/$d/nix/store" 2>/dev/null | wc -l)
  raw=$(du -sb "$W/x/$d" | cut -f1)
  printf '  %-26s %3d store paths  %6.1f MB unpacked\n' \
    "$d" "$n" "$(echo "scale=1; $raw/1048576" | bc 2>/dev/null || echo 0)"
done

echo
echo "== store-path overlap =="
first=1
for d in $SETUPS; do
  [ -d "$W/x/$d" ] || continue
  ls "$W/x/$d/nix/store" | sort > "$W/paths-$d"
  if [ "$first" = 1 ]; then
    cp "$W/paths-$d" "$W/union"
    cp "$W/paths-$d" "$W/common"
    first=0
  else
    sort -u "$W/union" "$W/paths-$d" -o "$W/union"
    sort "$W/common" > /tmp/c1
    comm -12 /tmp/c1 "$W/paths-$d" > "$W/common"
  fi
done

echo "  union of all store paths : $(wc -l < "$W/union")"
echo "  present in ALL setups    : $(wc -l < "$W/common")"
echo
echo "  the paths every setup ships:"
while read -r p; do
  sz=$(du -sb "$W/x/jq-1.8.2/nix/store/$p" 2>/dev/null | cut -f1)
  printf '    %8.1f MB  %s\n' "$(echo "scale=1; ${sz:-0}/1048576" | bc)" "${p#*-}"
done < "$W/common"
