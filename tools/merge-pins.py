"""merge-pins.py — carry CI-computed sha256 pins from a remote matrix.yml into
a locally edited one.

The CI `publish` job computes and commits the real sha256 for every asset. The
local working copy has those fields empty, so uploading it verbatim erased all
42 pins once: the release assets were still correct, but install.sh then refused
to unpack anything ("no pinned sha256").

A pin belongs to the ARTIFACT name. If the artifact is unchanged the pin is still
valid; if the artifact name changed the bytes changed too, so the stale pin is
dropped and the next publish recomputes it.
"""

import re


def _entries(text):
    """Yield dicts of the fields we care about, one per `- tool:` block."""
    cur = None
    for line in text.splitlines():
        m = re.match(r"^  - tool:\s*(\S+)", line)
        if m:
            if cur:
                yield cur
            cur = {"tool": m.group(1)}
            continue
        if cur is None:
            continue
        for f in ("version", "artifact", "sha256"):
            m2 = re.match(rf'^\s+{f}:\s*"?(.*?)"?\s*$', line)
            if m2:
                cur[f] = m2.group(1)
    if cur:
        yield cur


def merge_pins(local_text, remote_text):
    """Return (merged_text, count_of_pins_kept)."""
    remote_pins = {}
    for e in _entries(remote_text):
        if e.get("sha256"):
            remote_pins[(e.get("tool"), e.get("version"), e.get("artifact"))] = e["sha256"]

    lines = local_text.splitlines()
    cur = {}
    filled = 0
    for i, line in enumerate(lines):
        m = re.match(r"^  - tool:\s*(\S+)", line)
        if m:
            cur = {"tool": m.group(1)}
            continue
        for f in ("version", "artifact"):
            m2 = re.match(rf'^\s+{f}:\s*"?(.*?)"?\s*$', line)
            if m2:
                cur[f] = m2.group(1)
        m4 = re.match(r'^\s+sha256:\s*"?(.*?)"?\s*$', line)
        if m4:
            key = (cur.get("tool"), cur.get("version"), cur.get("artifact"))
            pin = remote_pins.get(key)
            if pin and not m4.group(1):
                lines[i] = f'    sha256: "{pin}"'
                filled += 1
    return "\n".join(lines) + "\n", filled
