#!/usr/bin/env bash
# run-container-test.sh — esegue tests/scenario.sh in un container ubuntu:24.04 pulito e usa e getta.
# Il container non ha systemd: attivazione dei timer, riavvii e login restano da provare su una VM (README).
set -euo pipefail
PKG=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=${IMAGE:-ubuntu:24.04}
docker run --rm --name setup-server-linux-test --hostname testsrv -v "$PKG:/pkg:ro" "$IMAGE" \
  bash -c 'apt-get update -qq >/dev/null && bash /pkg/tests/scenario.sh'
