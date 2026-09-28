#!/usr/bin/env bash
# sync-knowledge-base.sh — copia la Knowledge Base di un server di origine (fonte autorevole: /srv/ops/knowledge-base)
# nel payload del bootstrap e verifica che sia pubblicabile. Da usare sul server di origine prima di un rilascio.
#   tools/sync-knowledge-base.sh [SORGENTE]         (predefinita: /srv/ops/knowledge-base)
#   PRIVATE_PATTERNS=/percorso/file tools/...     file NON versionato con stringhe vietate del proprio server
#                                                  (indirizzi, domini, nomi): una per riga
# Si ferma se trova credenziali, chiavi, token o una stringa vietata; non pubblica nulla.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=${1:-/srv/ops/knowledge-base}; DST=payload/ops/knowledge-base
[ -f "$SRC/INDEX.md" ] || { echo "STOP: $SRC/INDEX.md assente" >&2; exit 3; }
bad=$(grep -rlE -- '-----BEGIN [A-Z ]*PRIVATE KEY|sk-(proj-)?[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|hc-ping\.com/[0-9a-f]{8}' "$SRC" || true)
[ -z "$bad" ] || { echo "STOP: possibili credenziali in: $bad" >&2; exit 3; }
if [ -n "${PRIVATE_PATTERNS:-}" ]; then
  bad=$(grep -rlF -f "$PRIVATE_PATTERNS" "$SRC" || true)
  [ -z "$bad" ] || { echo "STOP: stringhe riservate del server in: $bad" >&2; exit 3; }
fi
for f in $(find "$SRC" -name '*.md'); do d=$(dirname "$f")
  { grep -oE '\]\([^)#]+' "$f" || true; } | sed 's/](//' | { grep -v '^http' || true; } | while read -r l; do [ -e "$d/$l" ] || { echo "STOP: collegamento non risolto in $f: $l" >&2; exit 3; }; done
done
rm -rf "$DST"; mkdir -p "$DST"; cp -a "$SRC/." "$DST/"
echo "copiati $(find "$DST" -type f | wc -l) file da $SRC in $DST"
git status --short -- "$DST" | head -20
