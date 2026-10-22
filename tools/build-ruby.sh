#!/bin/bash
# build-ruby.sh <dir> <version> <outdir>
#
# Ruby from ruby/ruby-builder — the SAME prebuilt tarball GitHub Actions'
# ruby/setup-ruby uses. Nothing is compiled.
#
# Why an ubuntu tarball is right for a debian image:
#   ruby-builder publishes ubuntu-22.04/24.04/26.04 builds only. glibc is
#   BACKWARD compatible, so a binary linked against ubuntu 24.04's glibc 2.39
#   runs on debian trixie's 2.41. This was verified, not assumed: the unpacked
#   ruby reports "ruby 4.0.8 +PRISM [x86_64-linux]" and loads openssl, zlib,
#   digest and json on trixie.
#
# Three things the tarball needs that a plain `tar -x` does not give you, all
# of them fixed HERE so the consumer only ever unpacks:
#
#   1. libruby.so.4.0 is bundled but not on the default search path
#      -> the generated env.sh exports LD_LIBRARY_PATH (see install.sh).
#   2. bin/gem's shebang is an absolute path into GitHub's tool cache
#      (/opt/hostedtoolcache/Ruby/4.0.8/x64/bin/ruby) -> rewritten below to the
#      /opt/setup path this tree will live at.
#   3. RUBYLIB / GEM_HOME must point inside the tree -> also in env.sh.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

URL="https://github.com/ruby/ruby-builder/releases/download/ruby-${VERSION}/ruby-${VERSION}-ubuntu-24.04-x64.tar.gz"
echo "ruby: $DIR $VERSION <- $URL"
fetch "$URL" /tmp/ruby.tar.gz

# The archive's root is x64/; everything moves under /opt/setup/<dir>/.
rm -rf /tmp/ruby-x && mkdir -p /tmp/ruby-x
tar -xzf /tmp/ruby.tar.gz -C /tmp/ruby-x
cp -a /tmp/ruby-x/x64/. "$ROOT"/
rm -rf /tmp/ruby.tar.gz /tmp/ruby-x

# 2) Fix the shebangs. Every script in bin/ points at GitHub's tool cache; make
#    them point at the path this tree is installed to. `ruby -i` keeps the file
#    mode, which matters (they are executables).
PREFIX="/opt/setup/$DIR"
fixed=0
for f in "$ROOT"/bin/*; do
  [ -f "$f" ] || continue
  head -c 2 "$f" 2>/dev/null | grep -q '#!' || continue
  first=$(head -1 "$f")
  case "$first" in
    '#!'*hostedtoolcache*|'#!'*'/Ruby/'*)
      # Replace whatever interpreter line with this tree's ruby.
      sed -i "1s|.*|#!${PREFIX}/bin/ruby|" "$f"
      fixed=$((fixed + 1))
      ;;
  esac
done
echo "ruby: rewrote $fixed shebang(s) to ${PREFIX}/bin/ruby"

# Verify what the consumer will get, using the same environment env.sh sets.
export LD_LIBRARY_PATH="$ROOT/lib"
export RUBYLIB="$ROOT/lib/ruby/4.0.0:$ROOT/lib/ruby/4.0.0/x86_64-linux"
export GEM_HOME="$ROOT/lib/ruby/gems/4.0.0"
export GEM_PATH="$GEM_HOME"

"$ROOT/bin/ruby" --version
"$ROOT/bin/ruby" -e '
require "openssl"; require "zlib"; require "json"
puts "ruby ok: openssl=#{OpenSSL::OPENSSL_VERSION} json=#{JSON.generate({ok: true})}"
'

# `gem` and the other bin/ scripts now carry a shebang pointing at the FINAL
# install path (/opt/setup/<dir>/bin/ruby), which does not exist while the tree
# is still staged under /tmp. Running them by that shebang therefore fails here
# — but that is only a staging artefact, not a defect in the tarball. Invoke the
# script THROUGH the staged interpreter instead, which is what the consumer's
# `gem` ends up doing anyway.
"$ROOT/bin/ruby" "$ROOT/bin/gem" --version

# Prove the shebang the tarball ships is the final path, not the staging one.
if head -1 "$ROOT/bin/gem" | grep -q "^#!${PREFIX}/bin/ruby$"; then
  echo "ruby: gem shebang is $PREFIX/bin/ruby (final path) ok"
else
  echo "ruby: gem shebang is wrong: $(head -1 "$ROOT/bin/gem")" >&2
  exit 1
fi

mkdir -p "$OUT"
ASSET="$OUT/ruby-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "ruby: wrote $ASSET"
