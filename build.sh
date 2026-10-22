#!/bin/bash
# build.sh — build (and optionally push) every image declared in matrix.yml.
#
# matrix.yml is the single source of truth: this script reads it, derives the
# build args, and tags each image. Adding an image is therefore a one-line edit
# to matrix.yml, not a new pipeline branch.
#
#   ./build.sh                 build all, locally tagged
#   PUSH=1 ./build.sh          build and push to ghcr.io/easydev-org/easysetup
#   ONLY=node22 ./build.sh     build just one tag
set -euo pipefail

cd "$(dirname "$0")"
REGISTRY="${REGISTRY:-ghcr.io/easydev-org/easysetup}"
PUSH="${PUSH:-0}"
ONLY="${ONLY:-}"

need() { command -v "$1" >/dev/null || { echo "build.sh: $1 not found" >&2; exit 1; }; }
need docker
need python3

# matrix.yml -> one line per image: "<tag>\t<key=value key=value ...>"
python3 - <<'PY' > /tmp/easysetup-matrix.txt
import sys
try:
    import yaml
except ImportError:
    sys.exit("build.sh: python3 needs PyYAML (pip install pyyaml)")
doc = yaml.safe_load(open("matrix.yml"))
for img in doc.get("images", []):
    tag = img["tag"]
    tools = img.get("tools") or {}
    args = []
    for name, ver in tools.items():
        args.append(f"{name.upper()}_VERSION={ver}")
    print(tag + "\t" + " ".join(args))
PY

while IFS=$'\t' read -r tag args; do
  [ -n "$tag" ] || continue
  if [ -n "$ONLY" ] && [ "$ONLY" != "$tag" ]; then continue; fi

  # The TOOLS arg is the key set, in a stable order.
  tools=$(printf '%s\n' $args | sed 's/_VERSION=.*//' | tr 'A-Z' 'a-z' | sort | tr '\n' ' ')
  echo "=== $tag  ($tools) ==="

  build_args=(--build-arg "TOOLS=$tools")
  for kv in $args; do build_args+=(--build-arg "$kv"); done

  docker build "${build_args[@]}" -t "$REGISTRY:$tag" -f Dockerfile .

  # Smoke test what the image claims: every tool must answer --version from a
  # shell that only sourced env.sh. A silently broken toolchain is worse than a
  # missing image.
  echo "--- verifying $tag"
  docker run --rm "$REGISTRY:$tag" bash -lc '
    . /opt/setup/env.sh
    for t in node python3 go java; do
      if command -v "$t" >/dev/null; then "$t" --version 2>&1 | head -1; fi
    done
  '

  if [ "$PUSH" = "1" ]; then
    docker push "$REGISTRY:$tag"
  fi
done < /tmp/easysetup-matrix.txt

echo "build.sh: done"
