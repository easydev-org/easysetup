#!/bin/bash
# build-rust.sh <dir> <version> <outdir>
#
# Shared by two DIFFERENT setups, which is why it reads the target out of the
# directory name instead of taking it as an argument:
#
#   rust-1.99.1                              the host toolchain
#                                            -> rustc + cargo + host rust-std
#   rust-toolchain-x86_64-pc-windows-gnu-1.99.1
#                                            a cross-compile std only
#       the tool name carries the target as `rust-toolchain-<target>`, so
#       stripping that prefix gives the triple.
#
# rustup is deliberately NOT involved: components are unpacked directly, so
# nothing is resolved or fetched at install time.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"

# Derive the cross target from the setup name, if any.
TOOL="${DIR%-$VERSION}"
case "$TOOL" in
  rust-toolchain-*) TARGET="${TOOL#rust-toolchain-}" ;;
  rust)             TARGET="" ;;
  *) echo "rust: unexpected setup name '$DIR'" >&2; exit 1 ;;
esac
echo "rust: setup=$DIR target=${TARGET:-<host>}"

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT"

BASE="https://static.rust-lang.org/dist"
HOST=x86_64-unknown-linux-gnu

# Rust's component tarballs are self-extracting installers: they contain
# <comp>-<ver>-<target>/install.sh plus a component/ directory. Unpacking the
# tarball alone is not enough, so each one is extracted and its installer run
# with the destination prefix.
install_component() {
  comp="$1"
  tgt="$2"
  url="$BASE/${comp}-${VERSION}-${tgt}.tar.gz"
  echo "rust: component ${comp} for ${tgt} <- ${url}"
  fetch "$url" "/tmp/rust-${comp}.tar.gz"
  rm -rf "/tmp/rust-${comp}"
  mkdir -p "/tmp/rust-${comp}"
  tar -xzf "/tmp/rust-${comp}.tar.gz" -C "/tmp/rust-${comp}" --strip-components=1
  # The installer copies into <prefix> and needs no network.
  ( cd "/tmp/rust-${comp}" && ./install.sh --prefix="$ROOT" --disable-ldconfig ) \
    2>&1 | tail -2
  rm -rf "/tmp/rust-${comp}" "/tmp/rust-${comp}.tar.gz"
}

if [ -z "$TARGET" ]; then
  # Host toolchain: rustc, cargo and the host std. rust-std is what makes
  # `cargo build` work at all for the host triple.
  install_component rustc "$HOST"
  install_component cargo "$HOST"
  install_component rust-std "$HOST"
  # The rustc installer expects rust-std beside it; verify the pair really works.
  "$ROOT/bin/rustc" --version
  "$ROOT/bin/cargo" --version
  ( cd "$ROOT" && ./bin/rustc --print target-list >/dev/null )
else
  # A cross target: only the std for it is needed, and it lands in the tree's
  # lib/rustlib/<target>/ directory.
  install_component rust-std "$TARGET"
fi

mkdir -p "$OUT"
ASSET="$OUT/${TOOL}-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "rust: wrote $ASSET"
