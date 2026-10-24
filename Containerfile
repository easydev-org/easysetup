# A container with a shell, built from scratch, by easysetup.

# Not a distro: there is no /etc, no package manager, no libc outside /nix/store.
# The only thing in it is a nix store closure that easysetup put there, plus
# symlinks at the conventional paths so `sh` and `bash` behave as expected.

# Why two stages. easysetup is a static binary, but something has to download it,
# and a scratch image has nothing to download with. Stage 1 is therefore a small
# image that has a downloader; stage 2 keeps only the result.

# Why copying /nix works. Every binary in these closures names
# /nix/store/<hash>-glibc/lib/ld-linux-x86-64.so.2 as its ELF interpreter, and
# every library it needs is inside the same tree. The paths are absolute and
# self-contained, so copying /nix to the same absolute path in another image
# leaves it valid - nothing refers to stage 1's own userland.

# ----- stage 1: install --------------------------------------------------
# alpine, not busybox, and the difference is not aesthetic: busybox's wget is
# built without TLS in the official image, and GitHub serves releases only over
# HTTPS. alpine is ~3 MB compressed and has a real wget.
FROM alpine:3.21 AS installer

# easy-setup needs exactly one thing from this stage: a working HTTPS download.
# curl here rather than wget because we want it verified with a CA bundle.
RUN apk add --no-cache curl ca-certificates

ARG EASYSETUP_VERSION=
ARG TARGETARCH=amd64

RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) arch=amd64 ;; \
      arm64) arch=arm64 ;; \
      *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
    esac; \
    if [ -z "$EASYSETUP_VERSION" ]; then \
      EASYSETUP_VERSION=$(curl -fsSI https://github.com/easydev-org/easysetup-cli/releases/latest \
        | awk 'tolower($1)=="location:" {n=split($2,a,"/"); print a[n]; exit}'); \
    fi; \
    EASYSETUP_VERSION=$(printf '%s' "$EASYSETUP_VERSION" | tr -d '\r'); \
    [ -n "$EASYSETUP_VERSION" ] || { echo "could not resolve a version" >&2; exit 1; }; \
    echo "easysetup $EASYSETUP_VERSION for linux/$arch"; \
    base="https://github.com/easydev-org/easysetup-cli/releases/download/$EASYSETUP_VERSION"; \
    curl -fsSL -o /usr/local/bin/easysetup "$base/easysetup-linux-$arch"; \
    curl -fsSL -o /tmp/es.sha256 "$base/easysetup-linux-$arch.sha256"; \
    chmod +x /usr/local/bin/easysetup; \
    /usr/local/bin/easysetup checksum --check /tmp/es.sha256 /usr/local/bin/easysetup

# `prepare` is the one step needing root, and this stage has it. It creates
# /nix/store and makes it writable, which is all the install needs.
RUN /usr/local/bin/easysetup prepare
RUN /usr/local/bin/easysetup install bash busybox curl coreutils cacert

# One directory holds every symlink, and it is a directory this stage owns.
#
# Earlier versions wrote them into /usr/bin, which is alpine's - and stage 2's
# `COPY --from=installer /usr /usr` then dragged in alpine's entire userland,
# musl included, so the result was not scratch at all. /nix/bin is ours alone:
# /nix is the only tree stage 2 takes from this stage.
RUN set -eu; \
    mkdir -p /nix/bin; \
    for d in bash busybox curl coreutils; do \
      f="/nix/setup-root-$d"; \
      [ -f "$f" ] || { echo "no registry entry for $d" >&2; exit 1; }; \
      store=$(cut -d'|' -f1 "$f"); \
      [ "$store" = none ] && continue; \
      for b in "$store"/bin/*; do \
        [ -f "$b" ] || continue; \
        ln -sf "$b" "/nix/bin/$(basename "$b")"; \
      done; \
    done; \
    ln -sf "$(readlink -f /nix/bin/bash)" /nix/bin/sh; \
    /nix/bin/bash --version | head -1

# curl needs a CA bundle to speak HTTPS, and the curl closure does not carry one -
# certificates are data, not a library. Without this every https request from
# inside the image fails with "unable to get local issuer certificate", which
# reads like a broken network rather than a missing bundle.
RUN set -eu; \
    store=$(cut -d'|' -f1 /nix/setup-root-cacert-*); \
    cert="$store/etc/ssl/certs/ca-bundle.crt"; \
    [ -f "$cert" ] || { echo "no ca bundle at $cert" >&2; exit 1; }; \
    ln -sf "$cert" /nix/bin/ca-bundle.crt; \
    printf '%s\n' 'export PATH=/nix/bin' \
                  "export SSL_CERT_FILE=/nix/bin/ca-bundle.crt" > /nix/profile

# ----- stage 2: the image ------------------------------------------------
# scratch: nothing but what the previous stage produced.
FROM scratch

# Copied at the same absolute path, which is what keeps the ELF interpreter
# references inside the closures valid.
COPY --from=installer /nix /nix

# Everything comes from /nix and nowhere else. That is the whole point: no part
# of stage 1's userland reaches the final image, so there is no libc or shell
# here that easysetup did not put there.
COPY --from=installer /nix /nix

ENV PATH=/nix/bin
ENV SSL_CERT_FILE=/nix/bin/ca-bundle.crt
ENV BASH_ENV=/nix/profile

# busybox's sh, not bash: one static binary, and it works even if something is
# wrong with the bash closure. Override with --entrypoint /nix/bin/bash.
ENTRYPOINT ["/nix/bin/sh"]
