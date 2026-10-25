#!/bin/bash
# Reproduce the non-root extraction failure with nothing but mkdir.
#
# The report is "mkdir /nix/store/<hash>-bash-5.3p20/lib: permission denied"
# during install as a normal user. Two candidate causes, and they need different
# fixes:
#
#   A. the store path already exists and is owned by root (nobody but root can
#      write into it) - a permission problem, fixed by running as root
#   B. the extractor creates the directory with the archive's 0555 mode and then
#      tries to populate it - and the OWNER of a 0555 directory cannot create
#      files in it either. That is a bug in the extractor, not a privilege issue,
#      and it would fail for root-owned and user-owned trees alike.
#
# B is easy to overlook because root ignores permission bits, so a container
# never shows it.
set -uo pipefail

work=$(mktemp -d)
chmod 777 "$work"

# `su` rather than `sudo`: the sandbox this was developed in is root with no sudo
# installed, and su is present everywhere. The point is only to run as a normal
# user; which tool drops the privilege does not matter.
asnobody() { su -s /bin/bash nobody -c "$1"; }

echo "== B: create a directory 0555 and try to add a file to it, as its owner =="
mkdir -p "$work/store"
chmod 777 "$work/store"

asnobody "
  mkdir '$work/store/aaa-pkg' && chmod 0555 '$work/store/aaa-pkg'
  mkdir '$work/store/aaa-pkg/lib' 2>&1 || echo '  -> cannot create inside a 0555 dir it just made'
"

echo
echo "== A: a root-owned dir, same attempt =="
mkdir -p "$work/store/bbb-pkg"
chmod 755 "$work/store/bbb-pkg"
asnobody "
  mkdir '$work/store/bbb-pkg/lib' 2>&1 || echo '  -> cannot write into a root-owned dir'
"

echo
echo "== after: mkdir 0755 first, chmod at the end =="
asnobody "
  mkdir '$work/store/ccc-pkg' && mkdir '$work/store/ccc-pkg/lib' &&
    chmod 0555 '$work/store/ccc-pkg' && echo '  ok: populated first, mode applied after'
"

rm -rf "$work"
