#!/bin/bash
# End-to-end: two separate install.sh invocations, as two `uses:` steps would
# do, then check that BOTH tools survive and work.
set -euo pipefail
export HTTPS_PROXY=http://mihomo.develop.svc.cluster.local:7890
export HTTP_PROXY=$HTTPS_PROXY

WORK=$(mktemp -d)
# install.sh fetches matrix.yml / matrixlib.py / gen-env.sh over HTTP from the
# repo. Serve the local working copy over file:// and point it there, so this
# exercises the real code paths without hitting github.
SERVE=$(mktemp -d)
cp -r /tmp/es/matrix.yml /tmp/es/matrixlib.py "$SERVE/"
mkdir -p "$SERVE/tools"
cp /tmp/es/tools/gen-env.sh "$SERVE/tools/"

sed "s|^RAW=.*|RAW=\"file://$SERVE\"|" /tmp/es/install.sh > "$WORK/install.sh"

echo "=== invocation 1: node-22 ==="
bash "$WORK/install.sh" node-22 2>&1 | tail -6

echo ""
echo "=== invocation 2: python-3.12 ==="
bash "$WORK/install.sh" python-3.12 2>&1 | tail -6

echo ""
echo "=== env.sh after BOTH invocations ==="
head -50 /opt/setup/env.sh

echo ""
echo "=== do both work? ==="
(
  . /opt/setup/env.sh
  echo "node:   $(node --version)"
  echo "python: $(python3 --version)"
)

echo ""
echo "=== idempotence: node-22 again must skip the download ==="
bash "$WORK/install.sh" node-22 2>&1 | grep -E 'already installed|==>'

rm -rf "$WORK"
