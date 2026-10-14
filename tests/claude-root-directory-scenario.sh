#!/usr/bin/env bash
# Eseguire solo nel container usa e getta: verifica i permessi creati dal componente reale.
set -euo pipefail
src=${1:-/work/payload/ops/maint/install-claude-sandbox}
mkdir -p /var/lib/ops-bootstrap
chmod 0700 /var/lib/ops-bootstrap
export DIR=/tmp/ops-claude-directory-test
commands=$(awk '/^install -d -o root -g root -m / {print}' "$src")
bash -c "$commands"
[ "$(stat -c '%U:%G %a' /var/lib/ops-bootstrap)" = 'root:root 700' ]
[ "$(stat -c '%U:%G %a' "$DIR")" = 'root:root 755' ]
echo 'PASS: cartella integrita 0700 e componente eseguibile 0755'
