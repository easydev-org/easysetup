#!/bin/bash
# Which toolchains that we do NOT ship yet exist in the pinned nixpkgs?
#
# Now that adding a setup is one line, the question is only "does the attribute
# exist". Asking `.version` through the flake reads the LOCKED nixpkgs, so a hit
# here is exactly what the build would use - not whatever upstream published.
#
# Grouped by why someone would want them, so the output can be read as a
# shortlist rather than a wall of names.
set -uo pipefail
export HOME="${HOME:-/root}"
export NIX_CONFIG="experimental-features = nix-command flakes"
NIX=$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)
cd "$(dirname "$0")/.." || exit 1

probe() {
  local attr="$1" v
  # Quote the segment: some names contain dots, and nix reads an unquoted dot as
  # an attribute path separator.
  v=$("$NIX" eval --raw "nixpkgs#\"$attr\".version" 2>/dev/null) || v=""
  if [ -n "$v" ]; then
    printf '  %-32s %s\n' "$attr" "$v"
  else
    printf '  %-32s %s\n' "$attr" "-"
  fi
}

group() {
  echo "== $1 =="
  shift
  for a in "$@"; do probe "$a"; done
  echo
}

group "languages not shipped yet" \
  kotlin scala groovy clojure elm ocaml Racket chicken scheme guile racket \
  tcl hhvm pony raku red rebol factor forth

group "JVM / JVM tooling" \
  kotlin scala sbt mill ammonite jbang

group "C/C++ ecosystem" \
  gcc gcc13 gcc14 gcc15 llvm lldb valgrind cppcheck bear ccache distcc \
  meson autoconf automake libtool pkg-config make bison flex

group "build systems / task runners" \
  just task mask make cmake ninja meson samurai bazel buck2 pants please

group "containers / infra" \
  kubectl kubernetes-helm kustomize skaffold kind minikube podman buildah \
  skopeo docker-compose terraform opentofu ansible nixos-generators

group "cloud / k8s CLIs" \
  awscli2 azure-cli google-cloud-sdk doctl linode-cli hcloud

group "databases / clients" \
  postgresql mysql mariadb sqlite redis mongodb

group "protocol / api tooling" \
  protobuf grpcurl buf kong k6 vegeta hey wrk locust

group "servers / proxies" \
  nginx caddy haproxy envoy

group "lint / format / scan" \
  shellcheck shfmt hadolint yamllint markdownlint-cli2 prettier eslint \
  ruff black mypy pylint golangci-lint tflint tfsec trivy grype syft

group "editors / LSP" \
  neovim vim helix gopls nil nixd typescript-language-server

group "archives / text / misc CLI" \
  ripgrep fd bat eza zoxide fzf jq yq-go sd hyperfine tokei dust du-dust \
  bottom btop procs delta git gh glab pre-commit act

group "cross toolchains" \
  pkgsCross.mingwW64.buildPackages.gcc pkgsCross.aarch64-multiplatform.buildPackages.gcc
