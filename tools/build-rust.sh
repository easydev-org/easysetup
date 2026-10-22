#!/bin/bash
# build-rust.sh <dir> <version> <outdir>
#
# build-rust.sh <dir> <version> <outdir> [components...]
#
# Builds ONE /opt/setup tree out of the upstream rust components.
#
#   no components        rustc + cargo + rust-std for x86_64-unknown-linux-gnu
#                        -> the host toolchain
#   components given      rust-std for each named target only
#                        -> cross-compilation support, installed alongside
#
# `components` is the general "optional add-ons for a package" mechanism; for
# rust the add-ons are target std libraries (x86_64-pc-windows-gnu, ...).
#
# rustup is deliberately NOT involved: the components are unpacked directly, so
# nothing is resolved or fetched at install time.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"
shift 3
COMPONENTS=("$@")          # already split on whitespace by the caller

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

if [ "${#COMPONENTS[@]}" -eq 0 ]; then
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
  # One or more cross targets: only the std for each is needed, and it lands in
  # the host's lib/rustlib/<target>/ directory of THIS tree.
  for c in "${COMPONENTS[@]}"; do
    install_component rust-std "$c"
  done
fi

mkdir -p "$OUT"
STEM="rust-${VERSION}"
for c in "${COMPONENTS[@]}"; do
  STEM="${STEM}-${c}"
done
ASSET="$OUT/${STEM}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "rust: wrote $ASSET"
