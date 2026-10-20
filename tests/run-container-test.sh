#!/usr/bin/env bash
# run-container-test.sh — esegue tests/scenario.sh in un container ubuntu:24.04 pulito e usa e getta.
# Il container non ha systemd: attivazione dei timer, riavvii e login restano da provare su una VM (README).
set -euo pipefail
PKG=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=${IMAGE:-ubuntu:24.04}
SNAPSHOT=$(mktemp -d)
trap 'rm -rf -- "$SNAPSHOT"' EXIT
python3 "$PKG/tests/package-snapshot.py" "$PKG" "$SNAPSHOT/source.tar"
docker run --rm --name setup-server-linux-test --hostname testsrv -v "$SNAPSHOT/source.tar:/candidate.tar:ro" "$IMAGE" \
  bash -c 'mkdir /pkg && tar -xf /candidate.tar -C /pkg && apt-get update -qq >/dev/null && bash /pkg/tests/scenario.sh'
