#!/bin/bash
# Passo 9 — manutenzione automatica: parametri di /etc/ops-maint.conf e verifica, SENZA attivare nulla.
#
# Uso (terminale vero):
#   sudo bash /srv/ops/docs/bootstrap/passo9-manutenzione.sh --dry-run   # solo controlli
#   sudo bash /srv/ops/docs/bootstrap/passo9-manutenzione.sh             # REQUIRED_UNITS + VERIFY
#   sudo bash /srv/ops/docs/bootstrap/passo9-manutenzione.sh --rollback  # rimette /etc/ops-maint.conf di prima
#
# Unica modifica: REQUIRED_UNITS = unità di SERVICES in host.conf, che la finestra richiede abilitate all'avvio prima
# di riavviare ("ssh" diventa "ssh.socket|ssh.service", cioè una delle due; gli altri nomi "<nome>.service"). Si legge
# e si riscrive SOLO la riga di assegnazione (mai un grep sull'intero file, che trova anche i commenti); il valore
# attuale deve essere un sottoinsieme di quello previsto, altrimenti lo script si ferma. EXTRA_ORIGINS_RE ed
# EXTRA_BUSY_ARG_RE non vengono toccati (si impostano a mano quando la macchina ha repository o job propri).
# Nessuna unit ops-* viene abilitata: postboot prima del collaudo (passo 12.4), window e cli-update nel collaudo.
set -euo pipefail

CONF=/etc/ops-maint.conf
# copia propria del passo 9 (il passo 8 può averne creata una nello stesso giorno con il nome semplice)
BAK=$CONF.bak-$(date -u +%F)-passo9
STATE=/var/lib/ops-maint
MAINT=/usr/local/sbin/ops-maint
# shellcheck source=passi-comune.sh
. "$(dirname "$0")/passi-comune.sh"

MODE=apply
case "${1:-}" in "") ;; --dry-run) MODE=dry ;; --rollback) MODE=rollback ;; *) echo "argomento sconosciuto: $1" >&2; exit 2 ;; esac
die() { echo "ERRORE: $*" >&2; exit 1; }
ok() { echo "ok  $*"; }
ko() { echo "KO  $*"; bad=1; }
[ "$(id -u)" -eq 0 ] || die "va eseguito con sudo"
export LC_ALL=C.UTF-8
cur() { awk 'index($0, "REQUIRED_UNITS=") == 1 { print substr($0, 16); exit }' "$CONF"; }
attrs() { stat -c '%U:%G %a' -- "$1"; }
load_host_conf
NEW=""
for sv in $SERVICES; do
  case $sv in ssh|ssh.service) u='ssh.socket|ssh.service' ;; *.*) u=$sv ;; *) u=$sv.service ;; esac
  case " $NEW " in *" $u "*) ;; *) NEW="${NEW:+$NEW }$u" ;; esac
done
[ -n "$NEW" ] || die "SERVICES vuoto in $HOSTCONF"

if [ "$MODE" = rollback ]; then
  BAK=$(find /etc -maxdepth 1 -type f -name 'ops-maint.conf.bak-????-??-??-passo9' | sort | tail -1)
  [ -n "$BAK" ] && [ ! -L "$BAK" ] || die "nessuna copia $CONF.bak-*-passo9"
  cp -p -- "$BAK" "$CONF"; echo "ripristinato $CONF da $BAK: REQUIRED_UNITS=$(cur)"
  "$MAINT" origins >/dev/null && ok "parametri validi"
  exit 0
fi

echo "== PRECHECK"
bad=0
[ -f "$CONF" ] && [ ! -L "$CONF" ] && [ "$(attrs "$CONF")" = "root:root 644" ] || die "$CONF non è un file root 0644"
c=$(cur)
echo "  REQUIRED_UNITS attuale:   $c"
echo "  previsto (da SERVICES):  $NEW"
if [ "$c" = "$NEW" ]; then echo "REQUIRED_UNITS già al valore previsto: nessuna modifica"
else
  for t in $c; do case " $NEW " in *" $t "*) ;; *) die "REQUIRED_UNITS contiene '$t', che non deriva da SERVICES: da valutare a mano (host.conf o $CONF)" ;; esac; done
fi
for e in $NEW; do
  en=0; for u in ${e//|/ }; do systemctl is-enabled --quiet "$u" 2>/dev/null && en=1; done
  [ "$en" = 1 ] && ok "$e abilitato all'avvio" || ko "$e non abilitato all'avvio"
done
for u in ops-postboot.service ops-maint-window.timer ops-cli-update.timer; do
  [ "$(systemctl is-enabled "$u" 2>/dev/null)" = disabled ] && ok "$u disabilitato (resta così)" || ko "$u non disabilitato"
done
[ ! -e "$STATE/hold" ] && [ ! -e "$STATE/postboot-pending" ] && ok "nessuna sospensione né verifica pendente" || ko "hold o postboot-pending presenti"
grep -qx 'APPROVED=no' "$STATE/inbox/window.conf" && ok "finestra non approvata (APPROVED=no)" || ko "window.conf inatteso"
[ "$bad" -eq 0 ] || die "controlli non superati: nessuna modifica"
[ "$MODE" = dry ] && { echo "== DRY-RUN: nessuna modifica"; exit 0; }

echo "== BACKUP / MODIFICA"
if [ "$c" != "$NEW" ]; then
  if [ -e "$BAK" ]; then cmp -s "$CONF" "$BAK" || die "$BAK esiste ed è diverso da $CONF"; else cp -p -- "$CONF" "$BAK"; fi
  echo "  copia: $BAK"
  tmp=$(mktemp "$CONF.XXXXXX"); trap 'rm -f "$tmp"' EXIT
  awk -v new="$NEW" 'index($0, "REQUIRED_UNITS=") == 1 { print "REQUIRED_UNITS=" new; next } { print }' "$CONF" > "$tmp"
  chown root:root "$tmp"; chmod 0644 "$tmp"
  diff -u "$CONF" "$tmp" | sed 's/^/  /' || true
  mv -f -- "$tmp" "$CONF"
fi

echo "== VERIFY"
bad=0
[ "$(cur)" = "$NEW" ] && ok "REQUIRED_UNITS=$(cur)" || ko "REQUIRED_UNITS=$(cur)"
[ "$(attrs "$CONF")" = "root:root 644" ] && ok "$CONF root:root 0644" || ko "$CONF $(attrs "$CONF")"
"$MAINT" origins >/dev/null && ok "parametri validati da ops-maint (origini: $("$MAINT" origins))" || ko "parametri rifiutati da ops-maint"
h0=$(sha256sum < "$STATE/history.log")
rc=0; out=$(DRY_RUN=1 "$MAINT" window 2>&1) || rc=$?
echo "$out" | sed 's/^/  /'
[ "$rc" -eq 0 ] && ! grep -qiE 'non valido|deve essere|manca ' <<<"$out" && ok "DRY_RUN=1 ops-maint window: nessun errore di parametri" || ko "DRY_RUN window: codice $rc"
[ "$(sha256sum < "$STATE/history.log")" = "$h0" ] && [ ! -e "$STATE/hold" ] && ok "dry-run senza scritture nello stato (history.log invariato, nessun hold)" || ko "il dry-run ha scritto nello stato"
"$OPS/maint/install-maint" status 2>&1 | sed 's/^/  /'
echo "ESITO PASSO 9=$bad"
exit $bad
