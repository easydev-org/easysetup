#!/bin/bash
# install a JDK <version> under /opt/setup/java
#
# Adoptium Temurin. The API takes the feature release ("21") plus the exact
# version, and returns a redirect to the current build; pinning the full version
# ("21.0.8+9") keeps builds reproducible.
set -euo pipefail

VERSION="$1"
DEST=/opt/setup/java

# "21.0.8+9" -> feature "21", and the exact version for the API query.
FEATURE="${VERSION%%.*}"

URL="https://api.adoptium.net/v3/binary/version/jdk-${VERSION}/linux/x64/jdk/hotspot/normal/eclipse"
echo "java: ${VERSION} (feature ${FEATURE}) from Adoptium"

mkdir -p "$DEST"
if ! curl -fsSL --retry 3 --retry-delay 2 -o /tmp/jdk.tar.gz "$URL"; then
  echo "java: exact version ${VERSION} not available; falling back to the latest ${FEATURE} GA" >&2
  URL="https://api.adoptium.net/v3/binary/latest/${FEATURE}/ga/linux/x64/jdk/hotspot/normal/eclipse"
  curl -fsSL --retry 3 --retry-delay 2 -o /tmp/jdk.tar.gz "$URL"
fi

# The JDK tarball has one top-level directory (jdk-21.0.8+9/).
tar -xzf /tmp/jdk.tar.gz -C "$DEST" --strip-components=1
rm -f /tmp/jdk.tar.gz

"$DEST/bin/java" -version
