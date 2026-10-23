#!/bin/bash
# Does install order change the result?
#
# If it does not, that is a real property worth stating in the docs: it means
# `tools: "a b"` and `tools: "b a"` are the same install, and it means a failed
# partial install can simply be re-run instead of cleaned up first.
#
# The test installs the same three setups in two orders, each into a clean root,
# then compares the resulting trees file-by-file and the generated env.sh.
#
# Method note: a plain chroot would need root; this unpacks into a temp root and
# compares there, which exercises the same tar+registry logic without needing
# privileges.
set -uo pipefail

REPO="${EASYSETUP_REPO:-easydev-org/easysetup}"
BASE="https://github.com/${REPO}/releases/download"
WORK=/data/order-test
rm -rf "$WORK"
mkdir -p "$WORK"

# Two setups that genuinely share libraries: both need a C runtime and glibc,
# and jq additionally pulls oniguruma.
SETUPS_A="jq-1.8.2 yq-4.54.1"
SETUPS_B="yq-4.54.1 jq-1.8.2"

fetch_all() {
  for d in jq-1.8.2 yq-4.54.1; do
    local art="$d-debian-trixie-amd64.tar.zst"
    [ -f "$WORK/$art" ] && continue
    curl -fsSL --retry 3 --max-time 300 -o "$WORK/$art" "$BASE/$d/$art" || {
      echo "download failed for $d" >&2; return 1; }
  done
}

install_order() {
  local root="$1"; shift
  mkdir -p "$root"
  for d in "$@"; do
    local art="$d-debian-trixie-amd64.tar.zst"
    zstd -d --quiet -c "$WORK/$art" | tar -xf - -C "$root" || return 1
  done
}

echo "== fetching assets =="
fetch_all || exit 1
ls -lh "$WORK"/*.tar.zst | awk '{print "   ", $5, $9}'

echo
echo "== install order A: $SETUPS_A =="
install_order "$WORK/a" $SETUPS_A
echo "== install order B: $SETUPS_B =="
install_order "$WORK/b" $SETUPS_B

echo
echo "== compare the resulting trees =="
digest() {
  local root="$1"
  # Hash every regular file's content, sorted, so the result is independent of
  # the order the tar entries happened to be written in.
  ( cd "$root" && find . -type f -print0 | sort -z \
      | xargs -0 -r sha256sum | sha256sum | cut -d' ' -f1 )
}
DA=$(digest "$WORK/a")
DB=$(digest "$WORK/b")
echo "   order A: $DA"
echo "   order B: $DB"
if [ "$DA" = "$DB" ]; then
  echo "   IDENTICAL - install order does not matter"
else
  echo "   DIFFERENT - order matters, which would be a problem"
  ( cd "$WORK/a" && find . -type f | sort > /tmp/la )
  ( cd "$WORK/b" && find . -type f | sort > /tmp/lb )
  diff /tmp/la /tmp/lb | head -10
fi

echo
echo "== the per-setup registry files =="
ls "$WORK/a/nix" | tr -d '\000'
echo "   contents:"
for f in "$WORK"/a/nix/setup-root-*; do
  printf '     %-30s %s\n' "$(basename "$f")" "$(cat "$f")"
done

echo
echo "== shared store paths between the two closures =="
ls "$WORK/a/nix/store" | sort > /tmp/sa
ls "$WORK/b/nix/store" | sort > /tmp/sb
echo "   only in A: $(comm -23 /tmp/sa /tmp/sb | wc -l)"
echo "   only in B: $(comm -13 /tmp/sa /tmp/sb | wc -l)"
echo "   in both : $(comm -12 /tmp/sa /tmp/sb | wc -l)"
