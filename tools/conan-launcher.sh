#!/bin/sh
# conan launcher: run the CLI out of this setup tree.
#
# PYTHONPATH points at the tree's own lib/, which holds conan plus its vendored
# dependency closure. That keeps it independent of whatever site-packages the
# host python may or may not have - the same reasoning as GEM_HOME for ruby.
self=$(dirname "$(readlink -f "$0")")
root=$(cd "$self/.." && pwd)
PYTHONPATH="$root/lib${PYTHONPATH:+:$PYTHONPATH}" \
  exec "${EASYSETUP_PYTHON:-python3}" -c \
  'import sys; from conans.conan import run; sys.exit(run())' "$@"
