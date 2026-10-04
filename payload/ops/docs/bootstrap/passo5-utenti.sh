#!/bin/bash
# Passo 5 — utenti, gruppi e permessi dell'amministratore (sezione 5 della checklist).
#
# Uso (terminale vero; di norma lo lancia ops-installa):
#   sudo bash /srv/ops/docs/bootstrap/passo5-utenti.sh --dry-run   # solo controlli e piano
#   sudo bash /srv/ops/docs/bootstrap/passo5-utenti.sh             # PRECHECK + MODIFICA + VERIFY
#   sudo bash /srv/ops/docs/bootstrap/passo5-utenti.sh --rollback  # annulla le modifiche ai gruppi registrate
#
# Stato atteso: utenti con una shell di login solo root e l'amministratore (sync, con /bin/sync, è atteso);
# amministratore in sudo e adm, MAI in docker né in lxd (accesso equivalente a root senza password,
# docs/decisions.md); nessun NOPASSWD in /etc/sudoers e /etc/sudoers.d.
# Modifiche ammesse (solo sui gruppi dell'amministratore): aggiunta ad adm, rimozione da docker e lxd. Valgono dai
# login successivi. Un NOPASSWD o un altro utente con shell di login fermano lo script senza modifiche (da valutare
# a mano). Copia di /etc/group e /etc/gshadow (.bak-<data>) e manifest delle modifiche per il rollback.
set -euo pipefail

STATE_DIR=/var/lib/ops-bootstrap
MANIFEST=$STATE_DIR/passo5-utenti.manifest
BAK_SUFFIX=.bak-$(date -u +%F)
# shellcheck source=passi-comune.sh
. "$(dirname "$0")/passi-comune.sh"

MODE=apply
case "${1:-}" in "") ;; --dry-run) MODE=dry ;; --rollback) MODE=rollback ;; *) echo "argomento sconosciuto: $1" >&2; exit 2 ;; esac
die() { echo "ERRORE: $*" >&2; exit 1; }
ok() { echo "ok  $*"; }
ko() { echo "KO  $*"; bad=1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
attrs() { stat -c '%U:%G %a' -- "$1"; }
rec() { echo "$(now) $*" >> "$MANIFEST"; }
in_group() { id -nG "$ADMIN" | tr ' ' '\n' | grep -qx "$1"; }
check_state() {
  if [ -e "$STATE_DIR" ]; then [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ] && [ "$(attrs "$STATE_DIR")" = "root:root 700" ] || die "$STATE_DIR non è root 0700"; fi
  if [ -e "$MANIFEST" ]; then [ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] && [ "$(attrs "$MANIFEST")" = "root:root 600" ] || die "$MANIFEST non è root 0600"; fi
}
# utenti con una shell di login: esclusi nologin/false e sync (/bin/sync, utente di sistema atteso)
login_users() { getent passwd | awk -F: '$7 !~ /(nologin|false)$/ && !($1 == "sync" && $7 == "/bin/sync") {print $1}' | sort; }
nopasswd() { grep -rn NOPASSWD /etc/sudoers /etc/sudoers.d 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true; }

[ "$(id -u)" -eq 0 ] || die "va eseguito con sudo"
export LC_ALL=C.UTF-8
load_host_conf
check_state

if [ "$MODE" = rollback ]; then
  echo "== ROLLBACK"
  [ -f "$MANIFEST" ] || { echo "nessun manifest: questo script non ha modificato nulla"; exit 0; }
  # righe "<data> <add|del> <gruppo>": si annulla l'ultima azione registrata per ogni gruppo
  while read -r act g; do
    case $act in
      add) in_group "$g" && { gpasswd -d "$ADMIN" "$g" >/dev/null; rec undo-add "$g"; echo "tolto da $g"; } ;;
      del) getent group "$g" >/dev/null && ! in_group "$g" && { usermod -aG "$g" "$ADMIN"; rec undo-del "$g"; echo "rimesso in $g"; } ;;
    esac
  done < <(awk '$2 ~ /^(add|del|undo-add|undo-del)$/ {last[$3]=$2} END {for (g in last) if (last[g] !~ /^undo/) print last[g], g}' "$MANIFEST")
  id "$ADMIN"
  exit 0
fi

echo "== PRECHECK"
bad=0
echo "  $(id "$ADMIN")"
users=$(login_users | paste -sd' ')
want=$(printf '%s\n' root "$ADMIN" | sort | paste -sd' ')
[ "$users" = "$want" ] && ok "utenti con shell di login: $users (sync con /bin/sync atteso)" \
  || ko "utenti con shell di login: $users (attesi: $want) — da valutare a mano"
np=$(nopasswd)
[ -z "$np" ] && ok "nessun NOPASSWD in /etc/sudoers e /etc/sudoers.d" || { ko "NOPASSWD presente (rimuoverlo a mano dopo aver verificato sudo con password):"; echo "$np" | sed 's/^/    /'; }
in_group sudo && ok "$ADMIN nel gruppo sudo" || ko "$ADMIN non è nel gruppo sudo"
PLAN=()
in_group adm || PLAN+=("add adm")
for g in docker lxd; do in_group "$g" && PLAN+=("del $g"); done
[ "$bad" -eq 0 ] || die "controlli non superati: nessuna modifica"
if [ "${#PLAN[@]}" -eq 0 ]; then echo "  gruppi già conformi: nessuna modifica"
else for p in "${PLAN[@]}"; do case $p in "add "*) echo "  previsto: aggiungere $ADMIN a ${p#add }" ;; *) echo "  previsto: togliere $ADMIN da ${p#del } (equivale a root senza password)" ;; esac; done; fi
[ "$MODE" = dry ] && { echo "== DRY-RUN: nessuna modifica"; exit 0; }

if [ "${#PLAN[@]}" -gt 0 ]; then
  echo "== BACKUP"
  for f in /etc/group /etc/gshadow; do
    if [ -e "$f$BAK_SUFFIX" ]; then echo "  copia del giorno già presente: $f$BAK_SUFFIX"; else cp -p -- "$f" "$f$BAK_SUFFIX"; echo "  $f$BAK_SUFFIX"; fi
  done
  install -d -o root -g root -m 0700 -- "$STATE_DIR"; ( umask 077; : >> "$MANIFEST" ); chmod 0600 -- "$MANIFEST"
  echo "== MODIFICA"
  for p in "${PLAN[@]}"; do
    g=${p#* }
    case $p in
      "add "*) usermod -aG "$g" "$ADMIN"; rec add "$g"; echo "  aggiunto a $g" ;;
      "del "*) gpasswd -d "$ADMIN" "$g" >/dev/null; rec del "$g"; echo "  tolto da $g" ;;
    esac
  done
fi

echo "== VERIFY"
bad=0
in_group sudo && in_group adm && ok "$ADMIN in sudo e adm" || ko "$ADMIN: $(id -nG "$ADMIN")"
for g in docker lxd; do in_group "$g" && ko "$ADMIN ancora in $g" || ok "$ADMIN non è in $g"; done
for g in docker lxd; do
  if getent group "$g" >/dev/null; then m=$(getent group "$g" | cut -d: -f4); [ -z "$m" ] && ok "gruppo $g senza membri" || ko "gruppo $g con membri: $m"; fi
done
echo "  nota: i gruppi cambiati valgono dai login successivi"
echo "ESITO PASSO 5=$bad"
exit $bad
