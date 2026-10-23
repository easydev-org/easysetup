#!/usr/bin/env python3
"""Generate setups/<tool>.nix from matrix-nix.yml.

The refactor's shape is "one setup, one expression", but writing 40 near-identical
two-line files by hand invites drift (and a typo in one attribute is a CI round).
This generates them from the manifest, so the attribute name is written once.

Files that already exist are left alone: an entry may have been hand-edited to
add an override, and regeneration must not clobber that.

    tools/gen-setups.py [--force]
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import matrixlib2  # noqa: E402

TEMPLATE = """\
# Generated from matrix-nix.yml by tools/gen-setups.py.
#
# A setup is a nixpkgs attribute plus the name users type. Edit the manifest, not
# this file, unless the setup genuinely needs an override - in which case delete
# the "Generated" line above so regeneration leaves it alone.
{{ pkgs }}:
pkgs.{expr}
"""


def main(argv):
    force = "--force" in argv
    out = ROOT / "setups"
    out.mkdir(exist_ok=True)
    made = kept = 0
    for e in matrixlib2.load(str(ROOT / "matrix-nix.yml")):
        name = e["tool"]
        path = out / (name + ".nix")
        if path.exists():
            txt = path.read_text()
            if "Generated from matrix-nix.yml" not in txt and not force:
                print("keep  %s (hand-edited)" % path.name)
                kept += 1
                continue
        # `nixpkgs#swift` -> `swift`; anything with a dot or hash keeps its form.
        attr = e["attr"]
        expr = attr.split("#", 1)[1] if "#" in attr else attr
        path.write_text(TEMPLATE.format(expr=expr))
        print("write %s -> pkgs.%s" % (path.name, expr))
        made += 1
    print("\n%d written, %d kept" % (made, kept))


if __name__ == "__main__":
    main(sys.argv[1:])
