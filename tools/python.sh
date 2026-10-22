#!/bin/bash
# install python <version> under /opt/setup/python
#
# python-build-standalone (astral-sh): a self-contained CPython with its own
# libpython and stdlib. No compilation, no distro python, and it does not
# depend on the base image's glibc being a particular version beyond the
# "install_only" builds published for x86_64-unknown-linux-gnu.
set -euo pipefail

VERSION="$1"
DEST=/opt/setup/python

# The release tag and asset name carry the full version, e.g.
#   20250818/cpython-3.12.11+20250818-x86_64-unknown-linux-gnu-install_only.tar.gz
# Resolve the newest matching asset through the GitHub API so a version bump is
# a one-line change in matrix.yml.
echo "python: resolving ${VERSION} from python-build-standalone"
ASSET_URL=$(
  curl -fsSL --retry 3 "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest" \
  | python3 -c '
import json,sys
want="'"$VERSION"'"
rel=json.load(sys.stdin)
for a in rel.get("assets",[]):
    n=a["name"]
    if n.startswith("cpython-"+want+"+") and n.endswith("-x86_64-unknown-linux-gnu-install_only.tar.gz"):
        print(a["browser_download_url"]); break
'
)
if [ -z "$ASSET_URL" ]; then
  echo "python: no install_only build for ${VERSION} in the latest release" >&2
  exit 1
fi

echo "python: ${VERSION} from ${ASSET_URL}"
mkdir -p "$DEST"
curl -fsSL --retry 3 -o /tmp/python.tar.gz "$ASSET_URL"
# The archive contains python/ as its root.
tar -xzf /tmp/python.tar.gz -C /tmp
cp -a /tmp/python/. "$DEST"/
rm -rf /tmp/python /tmp/python.tar.gz

"$DEST/bin/python3" --version
