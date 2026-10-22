#!/bin/bash
# lib-relocate.sh — shared helper: repoint a staged tree's scripts at the path
# it will actually be installed to.
#
# Three setups hit this bug independently, each with a different symptom:
#
#   ruby  bin/gem    shebang -> /opt/hostedtoolcache/Ruby/... (GitHub's cache)
#   r     bin/R      R_HOME_DIR=/opt/R/<ver>/lib/R, and R IGNORES $R_HOME
#   ghc   bin/ghc    wrapper looks for lib/ghc-<ver>/bin/ghc-<ver> under the
#                    staging prefix, dies with "No such file or directory"
#   conda bin/conda  shebang -> the /tmp staging prefix; -p also refuses to
#                    reuse an existing directory
#
# The cause is always the same: the build records its install prefix into a
# script, the tree is packed, and it is unpacked somewhere else. Anything that
# does this must be rewritten BEFORE packing or the tarball is dead on arrival.
#
# Usage: relocate_scripts <staged-root> <final-prefix> [extra-old-prefix...]
# Prints the number of files it changed.
relocate_scripts() {
  local root="$1" prefix="$2"
  shift 2
  local olds=("$root" "$@")
  local changed=0 f old hit magic

  for f in "$root"/bin/* "$root"/condabin/*; do
    [ -f "$f" ] || continue
    # Never sed an ELF binary.
    magic=$(head -c 4 "$f" 2>/dev/null | od -An -c | tr -d ' ')
    [ "$magic" = "177ELF" ] && continue

    hit=0
    for old in "${olds[@]}"; do
      [ -n "$old" ] || continue
      if grep -qF "$old" "$f" 2>/dev/null; then
        sed -i "s|$old|$prefix|g" "$f"
        hit=1
      fi
    done
    # `[ ... ] && ...` would make the function's last status 1 when hit=0, and
    # every caller runs under `set -e`. Use an if.
    if [ "$hit" = 1 ]; then
      changed=$((changed + 1))
    fi
  done
  echo "$changed"
}
