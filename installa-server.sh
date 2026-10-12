#!/bin/bash
# Punto di ingresso locale del pacchetto: un solo comando dal terminale SSH.
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
[ "$(id -u)" != 0 ] || { echo 'Eseguire senza sudo: la procedura lo richiede al momento necessario.' >&2; exit 2; }
CONF=(); BOOT=(); CHECK=0
while [ $# -gt 0 ]; do
 case $1 in
  --profilo|--esclusioni) [ $# -ge 2 ] || exit 2; CONF+=("$1" "$2"); shift 2 ;;
  --agente|--owner|--kb-url) [ $# -ge 2 ] || exit 2; BOOT+=("$1" "$2"); shift 2 ;;
  --no-kb) BOOT+=(--no-kb); shift ;;
  --check) CHECK=1; BOOT+=(--check); shift ;;
  *) echo "Opzione non ammessa: $1" >&2; exit 2 ;;
 esac
done
sudo /bin/bash "$DIR/bootstrap.sh" --admin "$(id -un)" "${BOOT[@]}"
[ "$CHECK" = 0 ] || exit 0
exec /usr/local/bin/configura-server "${CONF[@]}"
