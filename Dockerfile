# easysetup — a toolchain image built from the pinned versions in matrix.yml.
#
# Build args are passed by build.sh from matrix.yml, so this file never carries a
# version of its own:
#
#   docker build --build-arg TOOLS="node python" \
#                --build-arg NODE_VERSION=22.20.0 ... -t easysetup:node22-python312
#
# Two rules this image keeps:
#   * the BASE layer is the only place apt is used, for the shared runtime
#     libraries the prebuilt toolchains need;
#   * every tool lands under /opt/setup/<tool> and nothing is installed into
#     /usr, so two toolchains can never collide and the base stays clean.
FROM debian:trixie

# Runtime libraries for the prebuilt distributions. Deliberately NOT node/python/
# java/go packages: those come from upstream tarballs so the version is exactly
# what matrix.yml says, not whatever the distro shipped.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils tar gzip \
      git openssh-client \
      build-essential pkg-config \
      libstdc++6 zlib1g libssl3 \
 && rm -rf /var/lib/apt/lists/*

ARG TOOLS=""
ARG NODE_VERSION=""
ARG PYTHON_VERSION=""
ARG GO_VERSION=""
ARG JAVA_VERSION=""

COPY tools/ /opt/easysetup/tools/
COPY env.sh.in /opt/easysetup/env.sh.in

# Install only the tools this image declares. `set -e` on each script means a
# failed download fails the BUILD, not some later CI run.
RUN set -eu; \
    for t in $TOOLS; do \
      case "$t" in \
        node)   bash /opt/easysetup/tools/node.sh   "$NODE_VERSION" ;; \
        python) bash /opt/easysetup/tools/python.sh "$PYTHON_VERSION" ;; \
        go)     bash /opt/easysetup/tools/go.sh     "$GO_VERSION" ;; \
        java)   bash /opt/easysetup/tools/java.sh   "$JAVA_VERSION" ;; \
        *) echo "easysetup: unknown tool '$t'" >&2; exit 1 ;; \
      esac; \
    done

# /opt/setup/env.sh exports exactly the tools that exist in this image.
RUN set -eu; \
    sed "s|@TOOLS@|$TOOLS|g" /opt/easysetup/env.sh.in > /opt/setup/env.sh; \
    chmod 0644 /opt/setup/env.sh; \
    rm -rf /opt/easysetup; \
    cat /opt/setup/env.sh

# Put the toolchains on PATH for `docker run` too (a CI job sources env.sh, but
# an interactive debug shell should just work).
ENV PATH=/opt/setup/node/bin:/opt/setup/python/bin:/opt/setup/go/bin:/opt/setup/java/bin:$PATH

LABEL org.opencontainers.image.source="https://github.com/easydev-org/easysetup" \
      org.opencontainers.image.description="easydev CI toolchain image"

CMD ["/bin/bash"]
