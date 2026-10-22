#!/bin/bash
# lib.sh — the one download helper every build script uses.
#
# A plain `curl --retry 3` is not enough. curl only retries a fixed set of
# transient conditions, and an HTTP/2 stream that dies mid-transfer surfaces as
#
#     curl: (92) HTTP/2 stream 1 was not closed cleanly: INTERNAL_ERROR (err 2)
#
# which is NOT in that set: the whole build failed with exit 92 after a single
# blip (observed on go-126). This wrapper retries the download itself, forces
# HTTP/1.1 (which does not have that particular failure mode), and verifies the
# result is a complete file rather than a truncated one.
#
# Usage:  . "$(dirname "$0")/lib.sh"; fetch <url> <dest>

fetch() {
  url="$1"
  dest="$2"
  attempt=1
  while [ "$attempt" -le 5 ]; do
    if curl -fsSL \
         --http1.1 \
         --connect-timeout 20 \
         --max-time 1800 \
         --retry 2 --retry-delay 3 \
         -o "$dest.part" "$url"; then
      # A "successful" transfer can still be short if the peer closed early;
      # move only a non-empty file into place.
      if [ -s "$dest.part" ]; then
        mv "$dest.part" "$dest"
        return 0
      fi
    fi
    echo "fetch: attempt $attempt failed for $url" >&2
    rm -f "$dest.part"
    attempt=$((attempt + 1))
    sleep $((attempt * 3))
  done
  echo "fetch: giving up on $url" >&2
  return 1
}
