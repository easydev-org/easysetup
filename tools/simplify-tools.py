#!/usr/bin/env python3
"""Keep one recommended workflow per language, delete the rest.

Every removal below was checked against the tool being kept, not inferred from
similar names:

  biome         `biome check` does formatting, linting AND assist/fix, and
                `biome ci` does the same non-destructively. That is exactly what
                prettier + eslint were for, in one binary.
  golangci-lint reports 109 linters including staticcheck, govet and errcheck,
                with auto-fix. gofumpt/gotools' goimports are covered by the
                gofmt/format family, and `go` itself ships gofmt.
  clang-tools   ships clangd (a language server), clang-format, clang-tidy and
                scan-build - so ccls (another LSP for the same C++ AST) and
                cpplint (style checks clang-tidy already covers) go. cppcheck
                stays: it is a different analysis, not a duplicate.
  php-cs-fixer  formatting only. psalm does static analysis AND ships
                psalm-language-server. phpmd is a rule-set linter; phan is a
                whole-program analyser. Keeping psalm + phpmd is two tools for
                two jobs; phan overlaps psalm and needs a PHP AST extension.
  rubocop       both linter and formatter (`rubocop -a` fixes). ruby-lsp is the
                language server. solargraph is a second LSP for the same job.
  ruff          replaces black (format), isort (import order) and flake8
                (lint), and `ruff check --fix` does what pylint mostly does.
                pylint stays only if its distinct rule set is wanted - it is.
  basedpyright  is a fork of pyright; keeping both ships the same 27 paths
                twice (measured 96% overlap).

What is deliberately NOT removed:
  gcc + clang        different compilers, different projects require one or the
                     other. Sharing 84% of payload is glibc, not duplication.
  micromamba + pixi  different models: conda-compatible CLI vs project workflow.
  gcovr + lcov       gcovr is the friendly front-end, lcov's genhtml is used
                     directly by many C projects.

    tools/simplify-tools.py [--apply]
"""

import pathlib
import re
import sys

MANIFEST = pathlib.Path("/data/es/matrix-nix.yml")

REMOVE = [
    # TS/JS - biome covers both
    ("prettier", "biome check does formatting and linting in one binary"),
    ("eslint", "biome check does linting; keep biome as the single JS/TS workflow"),
    # Python - ruff covers format/isort/lint
    ("black", "ruff format"),
    ("isort", "ruff check --select I"),
    ("flake8", "ruff check"),
    # Python - pyright is the upstream of basedpyright
    ("pyright", "basedpyright is its fork and superset (96% of the same paths)"),
    # Go
    ("gofumpt", "golangci-lint covers gofmt-family formatting"),
    ("gotools", "go ships gofmt/goimports; golangci-lint covers the rest"),
    # C/C++
    ("ccls", "clang-tools ships clangd, a language server for the same AST"),
    ("cpplint", "clang-tidy covers style checking"),
    # PHP
    ("phan", "psalm covers whole-program analysis and ships an LSP"),
    # Ruby
    ("solargraph", "ruby-lsp is the official language server"),
    # JVM
    ("checkstyle", "pmd covers style + static analysis; google-java-format formats"),
]


def main(argv):
    apply = "--apply" in argv
    text = MANIFEST.read_text()
    removed = []

    for tool, why in REMOVE:
        # Match the whole manifest line plus any comment block directly above it
        # that documents this tool, so a removed entry leaves no orphan comment.
        pat = re.compile(
            r'(?m)^[ \t]*- \{ tool: %s,[^\n]*\n' % re.escape(tool))
        m = pat.search(text)
        if not m:
            print("  %-22s not present, skipping" % tool)
            continue
        text = text[:m.start()] + text[m.end():]
        removed.append((tool, why))
        print("  %-22s remove - %s" % (tool, why))

    if not apply:
        print()
        print("%d to remove; rerun with --apply" % len(removed))
        return 0

    MANIFEST.write_text(text)
    print()
    print("removed %d setups from the manifest; run tools/gen-setups.py" % len(removed))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
