#!/bin/bash
# install node <version> under /opt/setup/node
#
# Official prebuilt tarball - Node ships a static Linux x64 build, so no
# compilation and no apt dependency on a distro's Node version.
set -euo pipefail

VERSION="$1"
DEST=/opt/setup/node
ARCH="linux-x64"
URL="https://nodejs.org/dist/v${VERSION}/node-v${VERSION}-${ARCH}.tar.xz"

echo "node: ${VERSION} from ${URL}"
mkdir -p "$DEST"
curl -fsSL --retry 3 --retry-delay 2 -o /tmp/node.tar.xz "$URL"

# Strip the tarball's top-level directory so the layout is /opt/setup/node/bin/node.
tar -xJf /tmp/node.tar.xz -C "$DEST" --strip-components=1
rm -f /tmp/node.tar.xz

"$DEST/bin/node" --version
