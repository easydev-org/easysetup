#!/bin/bash
# build-conan.sh <dir> <version> <outdir>
#
# Conan is a pure-Python application, and it is NOT self-contained: its
# METADATA declares ten runtime dependencies (requests, urllib3, colorama,
# PyYAML, patch-ng, fasteners, distro, Jinja2, python-dateutil, truststore) that
# a wheel does not carry. Unpacking only conan's own files produces a `conan`
# that dies on `import colorama`.
#
# So this vendors the whole dependency closure: every wheel is downloaded and
# unpacked into the same lib/, which is exactly what a venv would hold. Nothing
# is fetched at install time, and the launcher puts lib/ on PYTHONPATH rather
# than relying on the host's site-packages.
#
# It rides on a python setup (`requires: python@>=3.12,<4`), the same shape as
# elixir-on-erlang: the payload has no interpreter of its own.
set -euo pipefail

. "$(dirname "$0")/lib.sh"

DIR="$1"; VERSION="$2"; OUT="$3"

STAGE=$(mktemp -d)
ROOT="$STAGE/opt/setup/$DIR"
mkdir -p "$ROOT/lib" "$ROOT/bin"

HELPER="$(dirname "$0")/pypi-wheel-url.py"

# Fetch the newest wheel for a project, unpack it, and merge into lib/.
# The list below IS the dependency closure, spelled out from conan's own
# Requires-Dist, so the build is deterministic rather than resolver-driven.
add_wheel() {
  local pkg="$1"
  echo "conan: vendoring $pkg"
  local url
  url=$(python3 "$HELPER" "$pkg") || {
    echo "conan: cannot resolve a wheel for $pkg" >&2; return 1; }
  [ -n "$url" ] || { echo "conan: no wheel for $pkg" >&2; return 1; }
  curl -fsSL --http1.1 --retry 3 --max-time 180 -o /tmp/_w.whl "$url" || return 1
  unzip -q -o /tmp/_w.whl -d "$ROOT/lib"
  rm -f /tmp/_w.whl
}

# The dependency closure, taken from conan's own Requires-Dist. Pinned to the
# same major lines it declares.
add_wheel conan
for dep in requests urllib3 colorama PyYAML patch-ng fasteners distro Jinja2 \
           python-dateutil truststore certifi idna charset-normalizer \
           markupsafe six; do
  add_wheel "$dep"
done

# The launcher the wheel's entry_points.txt describes. Written from the repo
# copy so the script needs no heredoc (this shell has none).
cp "$(dirname "$0")/conan-launcher.sh" "$ROOT/bin/conan"
chmod +x "$ROOT/bin/conan"

# Prove the closure is complete by importing every dependency by name. A
# missing one here is exactly the failure this build exists to prevent.
python3 "$(dirname "$0")/conan-check.py" "$ROOT/lib" || {
  echo "conan: dependency closure incomplete" >&2; exit 1; }
echo "conan: $(ls "$ROOT/lib" | wc -l) package(s) in lib/"

mkdir -p "$OUT"
ASSET="$OUT/conan-${VERSION}-debian-trixie-amd64.tar.xz"
tar -cJf "$ASSET" -C "$STAGE" .
rm -rf "$STAGE"
echo "conan: wrote $ASSET ($(du -h "$ASSET" | cut -f1))"
