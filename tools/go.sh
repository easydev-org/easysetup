#!/bin/bash
# install go <version> under /opt/setup/go
set -euo pipefail

VERSION="$1"
DEST=/opt/setup/go
URL="https://go.dev/dl/go${VERSION}.linux-amd64.tar.gz"

echo "go: ${VERSION} from ${URL}"
mkdir -p "$DEST"
curl -fsSL --retry 3 --retry-delay 2 -o /tmp/go.tar.gz "$URL"
tar -xzf /tmp/go.tar.gz -C "$DEST" --strip-components=1
rm -f /tmp/go.tar.gz

"$DEST/bin/go" version
