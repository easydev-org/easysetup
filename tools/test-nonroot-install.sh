#!/bin/bash
# Install as a normal user, as a plain runner does, and run the tools.
#
# This exists because two separate bugs were only reachable that way, and both
# looked fixed when tested as root:
#
#   1. the extractor created directories with the archive's 0555 mode and then
#      tried to populate them - its own owner cannot write into that
#   2. two setups can carry the SAME store path (java and maven both contain
#      set-java-classpath-hook), so whichever installs second found it 0444 and
#      failed to replace it
#
# Root ignores permission bits, so a container passes both and a runner fails both.
# Any smoke test that runs as root is therefore not testing the installer.
#
# The setups below are chosen for the failure modes, not for convenience: java +
# maven is the shared-store-path case, and the others pull in enough of a
# dependency chain to exercise the depth-first install order.
set -uo pipefail

BIN=${BIN:-/tmp/easysetup}
[ -x "$BIN" ] || { echo "need an easysetup binary at $BIN (set BIN=...)" >&2; exit 1; }

pass=0
fail=0

ok()   { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

# Creating /nix needs root, and that is the ONE thing the test allows itself.
# Everything after it runs as nobody, which is the point.
#
# sudo, not su: a GitHub runner's sudo is passwordless, while su to another user
# prompts for a password it does not have. In the sandbox this was developed in the
# shell was already root, so `su nobody` worked there and not here - which is the
# same "only fails where it matters" shape as the bug this test guards.
#
# Each case gets a fresh store so the "already installed" logic does not mask a
# failure by skipping the write entirely.
fresh_store() {
  sudo rm -rf /nix /tmp/nb-home
  sudo mkdir -p /nix/store
  sudo chmod 777 /nix /nix/store
  mkdir -p /tmp/nb-home
  chmod 777 /tmp/nb-home
}

# Run as nobody, with HOME somewhere writable - the runner's own home is not.
as_nobody() { sudo -u nobody env HOME=/tmp/nb-home bash -c "$*"; }

# Every install is bounded. A hung download would otherwise run until the job's
# overall timeout, hiding which setup it was and why - and one of these closures is
# 200+ paths, so "slow" and "stuck" look identical without a limit.
INSTALL_TIMEOUT=${INSTALL_TIMEOUT:-600}

echo "== install as a normal user =="
for combo in "jq" "java maven" "node" "python pip" "elixir erlang" "micromamba pixi"; do
  fresh_store
  echo "  -- $combo"
  out=$(as_nobody "timeout $INSTALL_TIMEOUT $BIN install $combo" 2>&1)
  if echo "$out" | grep -q "installed:"; then
    ok "$combo installs"
  else
    bad "$combo"
    echo "$out" | tail -6 | sed 's/^/        /'
  fi
done

echo
echo "== and the tools actually run =="
# java+maven is the pair that used to fail; if its jars and scripts resolve, the
# shared store path really was written correctly.
fresh_store
as_nobody "$BIN install java maven" >/dev/null 2>&1
as_nobody "$BIN env /tmp/nb-home/e.sh" >/dev/null 2>&1
for check in "java -version:openjdk" "mvn -version:Apache Maven"; do
  cmd=${check%%:*}; want=${check##*:}
  got=$(as_nobody ". /tmp/nb-home/e.sh && $cmd 2>&1" | head -2 | tr '\n' ' ')
  case "$got" in
    *"$want"*) ok "$cmd says $want" ;;
    *) bad "$cmd (got: ${got:0:60})" ;;
  esac
done

echo
echo "== the store is left readable, not 000 =="
mode=$(stat -c '%a' /nix/store)
case "$mode" in
  *7*|*5*) ok "/nix/store is $mode" ;;
  *) bad "/nix/store is $mode - later installs will fail" ;;
esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
