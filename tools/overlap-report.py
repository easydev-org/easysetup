#!/usr/bin/env python3
"""How much do these setups actually duplicate each other?

Functional overlap is not the same as byte overlap. `gcc` and `clang` are two
compilers that do the same job but share nothing; `pyright` and `basedpyright`
are a fork and its upstream, so they share most of their size. Only the
second kind is waste, so this measures the closures rather than the descriptions.

Three numbers per pair:
  shared   bytes the two closures have in common
  overlap  that as a fraction of the smaller one - 100% means one is entirely
           contained in the other
  verdict  whether they are the same program twice, or two answers to one question

    tools/overlap-report.py <dir> <dir> [<dir> <dir> ...]
    tools/overlap-report.py --groups          # the pairs worth looking at
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Pairs that look like duplicates from the names alone. Whether they are is what
# the measurement decides.
GROUPS = [
    ("TS/JS package managers", ["pnpm-12.9.0", "yarn-1.22.22", "bun-1.4.2"]),
    ("TS/JS lint + format", ["biome-2.5.15", "prettier-3.9.10", "eslint-10.12.0"]),
    ("python lint + format", ["ruff-0.17.1", "black-26.5.1", "flake8-7.3.0",
                               "isort-8.0.1", "pylint-4.0.7"]),
    ("python type check", ["pyright-1.1.414", "basedpyright-1.39.8",
                           "mypy-2.1.0"]),
    ("python env + install", ["pip-26.1.2", "virtualenv-21.6.1", "uv-0.13.1"]),
    ("conda-compatible", ["micromamba-2.9.0", "pixi-0.82.0"]),
    ("C compilers", ["gcc-16.2.0", "clang-23.1.3"]),
    ("C/C++ static analysis", ["cppcheck-2.22.0", "cpplint-2.0.2",
                               "clang-tools-23.1.3"]),
    ("C/C++ coverage", ["gcovr-8.4", "lcov-2.4"]),
    ("C/C++ LSP", ["ccls-0.20250815.1", "clang-tools-23.1.3"]),
    ("PHP static analysis", ["psalm-6.18.0", "phan-6.0.7", "phpmd-2.15.0"]),
    ("Ruby LSP", ["ruby-lsp-0.26.3", "solargraph-0.57.0"]),
    ("Rust lint + format", ["rustfmt-1.99.0", "clippy-1.99.0",
                            "rust-analyzer-2026-10-12"]),
    ("JS LSP", ["typescript-language-server-6.0.2",
                "vscode-langservers-1.140.06880"]),
    ("download", ["curl-8.22.0", "wget-1.25.0"]),
    ("archives", ["zip-3.0", "unzip-6.0", "xz-5.8.4", "zstd-1.5.7"]),
    ("yaml/json format", ["yamllint-1.37.1", "yamlfmt-0.21.0"]),
    ("build systems", ["cmake-4.4.4", "meson-1.12.1", "bazel-7.6.0"]),
    ("JVM build tools", ["maven-3.9.16", "gradle-9.8.0", "sbt-2.0.10"]),
    ("linkers", ["mold-3.0.0", "bintools-23.1.3"]),
    ("shell", ["shellcheck-0.11.0", "shfmt-3.14.1"]),
    ("JSON/XML CLI", ["jq-1.8.2", "yq-4.54.1", "jqp-0.8.0", "dasel-3.11.2"]),
]


def main(argv):
    doc = json.load(open(matrixlib2.closures_path(ROOT)))
    setups = doc["setups"]
    base = set(doc.get("base", []))

    pairs = []
    if argv and argv[0] != "--groups":
        pairs = [(argv[i], argv[i + 1]) for i in range(0, len(argv) - 1, 2)]

    for label, group in GROUPS:
        have = [g for g in group if g in setups]
        if len(have) < 2:
            continue
        print("== %s" % label)
        # Show each one's own payload first: that is what it costs on its own.
        for g in have:
            e = setups[g]
            print("   %-34s own %4d paths, closure %4d" % (g, len(e["own"]), e["closure_size"]))
        # Then the pair-wise containment among them.
        print()
        for i in range(len(have)):
            for k in range(i + 1, len(have)):
                a, b = have[i], have[k]
                ca = set(setups[a]["own"]) | (base & set(setups[a]["own"]))
                # Compare FULL closures, which is what "same program twice" means.
                ja = json.loads(json.dumps(setups[a]))
                jb = json.loads(json.dumps(setups[b]))
                oa = set(setups[a]["own"])
                ob = set(setups[b]["own"])
                inter = oa & ob
                smaller = min(len(oa), len(ob)) or 1
                frac = 100.0 * len(inter) / smaller
                note = ""
                if frac >= 90:
                    note = "  <-- one is essentially contained in the other"
                elif frac >= 40:
                    note = "  <-- substantial shared payload"
                print("   %-28s vs %-28s shared %3d paths (%3.0f%%)%s"
                      % (a.split("-")[0], b.split("-")[0], len(inter), frac, note))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
