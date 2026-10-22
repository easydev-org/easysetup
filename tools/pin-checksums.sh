#!/bin/bash
# pin-checksums.sh <assets-dir> — write the sha256 of every asset into matrix.yml
# and push the result to main.
#
# Run by the release workflow AFTER the releases are published.
#
# Why this is a script and not inline YAML: it needs a loop, a retry and a
# heredoc, all inside `run: |`, and the heredoc's indentation has to be exactly
# right or the YAML parser folds it into nonsense. Keeping it in a file makes
# the indentation a non-issue and the whole thing testable locally.
#
# The edit is made on the LATEST main rather than on the job's checkout. The
# checkout is from when the run started and main moves (another push, a previous
# publish); rewriting the stale copy and then rebasing conflicted on matrix.yml
# because the very lines it touched had already changed.
set -euo pipefail

ASSETS="${1:-/tmp/assets}"
MATRIX=matrix.yml

git config user.name  "easysetup-bot"
git config user.email "easysetup-bot@users.noreply.github.com"

pin() {
  python3 - "$ASSETS" <<'PY'
import glob, hashlib, os, re, sys

sys.path.insert(0, ".")
import matrixlib

assets = sys.argv[1]
# artifact name -> derived dir, so the digest is written into the block whose
# `artifact:` matches, without re-deriving the name here.
by_artifact = {e["artifact"]: e for e in matrixlib.load()}
text = open("matrix.yml").read()
pinned = 0
for path in sorted(glob.glob(os.path.join(assets, "*.tar.xz"))):
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
    name = os.path.basename(path)
    if name not in by_artifact:
        sys.exit(f"pin-checksums: {name} is not referenced by matrix.yml")
    # Anchor on the artifact name so each setup gets its own digest.
    pattern = re.compile(r'(artifact: ' + re.escape(name) + r'\n\s+sha256: )"[^"]*"')
    text, n = pattern.subn(r'\1"' + digest + '"', text)
    if n != 1:
        # A published asset that matrix.yml does not name means the two have
        # drifted; say so instead of silently pinning nothing.
        sys.exit(f"pin-checksums: {name} is not referenced by matrix.yml")
    print(f"{name} -> {digest[:16]}...")
    pinned += n
open("matrix.yml", "w").write(text)
print(f"pin-checksums: {pinned} checksum(s)")
PY
}

for attempt in 1 2 3; do
  git fetch origin main
  git checkout -B checksum-pin origin/main
  pin

  if git diff --quiet "$MATRIX"; then
    echo "matrix.yml already carries these checksums"
    exit 0
  fi

  git add "$MATRIX"
  git commit -m "chore(matrix): pin sha256 for the published assets"
  if git push origin HEAD:main; then
    echo "checksums pushed on attempt $attempt"
    exit 0
  fi
  echo "push rejected on attempt $attempt; refetching main"
  sleep 5
done

echo "pin-checksums: could not push the checksum commit" >&2
exit 1
