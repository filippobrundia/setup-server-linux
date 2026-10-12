#!/usr/bin/env bash
# install.sh — punto di ingresso pubblico di setup-server-linux.
#
#   curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.7.0/install.sh \
#     | bash -s -- --sha256 <IMPRONTA DALLA PAGINA DELLA RELEASE> [--check] [--owner "Nome"] [--knowledge-base-only]
#                  [--no-kb | --kb-url https://host/percorso]   (Knowledge Base facoltativa: senza opzioni la domanda arriva durante l'avvio)
#                  [--agente claude|codex|agy|gemini]          (agente della sessione: senza opzione la domanda arriva alla fine)
#
# Da eseguire come utente amministratore NORMALE (nel gruppo sudo), mai come root: gli agenti e i loro login
# restano in questo account. Scarica la release v$VERSION, ne verifica l'integrità (SHA256SUMS della release e,
# con --sha256, l'impronta pubblicata), la estrae in ~/setup-server-linux-$VERSION e avvia
# "sudo bootstrap.sh --admin <questo utente>" (sudo chiede la password). --check: solo controllo, nessuna modifica.
set -euo pipefail
REPO=filippobrundia/setup-server-linux
VERSION=0.7.0
NAME=setup-server-linux-$VERSION
BASE=https://github.com/$REPO/releases/download/v$VERSION

die() { echo "STOP: $*" >&2; exit 3; }
WANT=""; ARGS=()
CONFIGURA=0; CONFARGS=()
while [ $# -gt 0 ]; do
  case $1 in
    --configura) CONFIGURA=1; shift ;;
    --profilo|--esclusioni) [ $# -ge 2 ] || die "manca il valore di $1"; CONFARGS+=("$1" "$2"); shift 2 ;;
    --sha256) WANT=${2:-}; shift 2 ;;
    --check)  ARGS+=(--check); shift ;;
    --owner)  ARGS+=(--owner "${2:-}"); shift 2 ;;
    --knowledge-base-only) ARGS+=(--knowledge-base-only); shift ;;
    --no-kb)  ARGS+=(--no-kb); shift ;;
    --kb-url) ARGS+=(--kb-url "${2:-}"); shift 2 ;;
    --agente) ARGS+=(--agente "${2:-}"); shift 2 ;;
    *) die "opzione sconosciuta: $1" ;;
  esac
done

if [ "$CONFIGURA" = 0 ] && [ "${#CONFARGS[@]}" -gt 0 ]; then die "--profilo e --esclusioni richiedono --configura"; fi
if [ "$CONFIGURA" = 1 ]; then
  for a in "${ARGS[@]}"; do case $a in --check|--knowledge-base-only) die "--configura non si combina con $a" ;; esac; done
fi

[ "$(id -u)" != 0 ] || die "eseguire come utente amministratore normale, non come root (gli agenti vanno installati nel suo account)"
ME=$(id -un)
g=" $(id -nG) "; [[ "$g" == *" sudo "* ]] || die "$ME non è nel gruppo sudo"
for c in curl sha256sum tar sudo; do command -v "$c" >/dev/null || die "manca il comando $c"; done
[ -z "$WANT" ] || [[ "$WANT" =~ ^[0-9a-f]{64}$ ]] || die "--sha256 deve essere un'impronta SHA-256 (64 cifre esadecimali)"

DEST=$HOME/$NAME
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
echo "== scarico $NAME"
curl -fsSL --proto '=https' -o "$TMP/$NAME.tar.gz" "$BASE/$NAME.tar.gz"
curl -fsSL --proto '=https' -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS"
GOT=$(sha256sum "$TMP/$NAME.tar.gz" | cut -d' ' -f1)
SUM=$(awk -v f="$NAME.tar.gz" '$2 == f || $2 == "*" f {print $1}' "$TMP/SHA256SUMS")
[ -n "$SUM" ] && [ "$GOT" = "$SUM" ] || die "l'archivio non corrisponde a SHA256SUMS della release"
if [ -n "$WANT" ]; then
  [ "$GOT" = "$WANT" ] || die "impronta diversa da quella indicata con --sha256 ($GOT)"
  echo "   integrità verificata: $GOT (impronta pubblicata e SHA256SUMS)"
else
  echo "   integrità verificata solo contro SHA256SUMS della stessa release: $GOT"
  echo "   (per una verifica indipendente usare --sha256 con l'impronta della pagina della release)"
fi

if [ -e "$DEST" ]; then
  [ -f "$DEST/.archive-sha256" ] && [ "$(cat "$DEST/.archive-sha256")" = "$GOT" ] \
    || die "$DEST esiste e non proviene da questo archivio: spostarlo o rimuoverlo e rieseguire"
  echo "== uso $DEST (già estratto dallo stesso archivio)"
else
  tar -xzf "$TMP/$NAME.tar.gz" -C "$TMP"
  [ -x "$TMP/$NAME/bootstrap.sh" ] || die "archivio senza bootstrap.sh"
  echo "$GOT" > "$TMP/$NAME/.archive-sha256"
  mv "$TMP/$NAME" "$DEST"
  echo "== estratto in $DEST"
fi

echo "== avvio: sudo $DEST/bootstrap.sh --admin $ME ${ARGS[*]:-}"
if [ "$CONFIGURA" = 1 ]; then
  for a in "${ARGS[@]}"; do case $a in --check|--knowledge-base-only) die "--configura non si combina con $a" ;; esac; done
  sudo "$DEST/bootstrap.sh" --admin "$ME" "${ARGS[@]}" < /dev/tty
  exec /usr/local/bin/configura-server "${CONFARGS[@]}" < /dev/tty
else
  if [ -r /dev/tty ]; then exec sudo "$DEST/bootstrap.sh" --admin "$ME" "${ARGS[@]}" < /dev/tty
  else exec sudo "$DEST/bootstrap.sh" --admin "$ME" "${ARGS[@]}"; fi
fi
