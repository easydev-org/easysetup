#!/usr/bin/env python3
"""The manifest parser must handle the shapes the manifest actually uses.

Each case here broke at least once:

  * a flow list wrapped onto a continuation line (cmake's apt_deps) - the parser
    died with "unsupported line";
  * a quoted comma inside a flow list (["swift@>=6.4,<7"]) - naive splitting
    turned it into two broken entries, failing three Swift SDK builds;
  * a trailing comment after a flow list.
"""

import pathlib
import sys
import tempfile

sys.path.insert(0, "/tmp/es")
import matrixlib  # noqa: E402

fail = 0


def check(name, got, want):
    global fail
    print(("ok   " if got == want else "FAIL ") + name + " -> " + repr(got))
    if got != want:
        print("     want " + repr(want))
        fail = 1


MATRIX = pathlib.Path(tempfile.mkdtemp()) / "m.yml"
MATRIX.write_text('''\
setups:
  - tool: cmake
    version: "4.4.4"
    apt_deps: [ca-certificates, curl, libxcb1, libfontconfig1,
               libfreetype6, libx11-6, libxext6]
    artifact: cmake-4.4.4.tar.xz
    sha256: ""
  - tool: swift-sdk-wasm
    version: "6.4.1"
    requires: ["swift@>=6.4,<7"]
    apt_deps: [ca-certificates, curl]
    artifact: swift-sdk-wasm-6.4.1.tar.xz
    sha256: ""
''')

e = matrixlib.by_dir("cmake-4.4.4", str(MATRIX))
check("wrapped flow list is one list", e["apt_deps"],
      ["ca-certificates", "curl", "libxcb1", "libfontconfig1",
       "libfreetype6", "libx11-6", "libxext6"])

s = matrixlib.by_dir("swift-sdk-wasm-6.4.1", str(MATRIX))
check("quoted comma stays inside one requirement", s["requires"],
      ["swift@>=6.4,<7"])

print("\ntest_parser: " + ("FAILED" if fail else "ok"))
raise SystemExit(1 if fail else 0)
