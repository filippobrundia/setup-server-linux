#!/bin/bash
# Passo 10 (completamento) — rotazione di /var/log/borgmatic.log, prova reale della rotazione, secondo backup e
# verifica del ripristino con la configurazione definitiva (cron e logrotate inclusi nell'archivio).
#
# Uso (terminale vero, fuori da 03:00–04:10 UTC):
#   sudo bash /srv/ops/docs/bootstrap/passo10b-rotazione-verifica.sh
#   sudo bash /srv/ops/docs/bootstrap/passo10b-rotazione-verifica.sh --rollback   # toglie solo il file logrotate
#
# 1. /etc/logrotate.d/borgmatic dal modello maint/templates/logrotate-borgmatic: settimanale, 8 copie, compressione
#    ritardata (il log precedente resta leggibile da quick-check, che lo consulta se il log corrente non contiene
#    ancora un archivio), "create 0644 root root".
# 2. Prova reale: rotazione forzata del solo log di borgmatic; quick-check come amministratore deve ancora trovare
#    l'archivio (nel log ruotato). Nessun log viene cancellato.
# 3. Secondo backup e prova di ripristino: ripresa di passo10-backup.sh (non reinstalla nulla di esistente).
set -euo pipefail

LR=/etc/logrotate.d/borgmatic
LOG=/var/log/borgmatic.log
MANIFEST=/var/lib/ops-bootstrap/passo10-backup.manifest
# shellcheck source=passi-comune.sh
. "$(dirname "$0")/passi-comune.sh"
LR_SRC=$TEMPLATES/logrotate-borgmatic
P10=$(dirname "$0")/passo10-backup.sh

die() { echo "ERRORE: $*" >&2; exit 1; }
ok() { echo "ok  $*"; }
ko() { echo "KO  $*"; bad=1; }
attrs() { stat -c '%U:%G %a' -- "$1"; }
[ "$(id -u)" -eq 0 ] || die "va eseguito con sudo"
export LC_ALL=C.UTF-8
load_host_conf

if [ "${1:-}" = --rollback ]; then
  [ -f "$LR" ] && cmp -s "$LR" "$LR_SRC" && { mv -f -- "$LR" "$LR.rollback-$(date -u +%F)"; echo "spostato $LR"; } || echo "nulla da fare"
  exit 0
fi
[ -z "${1:-}" ] || die "argomento sconosciuto: $1"

echo "== PRECHECK"
bad=0
h=$(date -u +%H%M); [ "$h" -lt 0300 ] || [ "$h" -ge 0410 ] || die "03:00–04:10 UTC: finestra del backup notturno"
[ -f "$MANIFEST" ] && [ "$(attrs "$MANIFEST")" = "root:root 600" ] || die "manca il manifest del passo 10"
for f in /etc/borgmatic/config.yaml /usr/local/bin/run-borgmatic.sh /etc/cron.d/borgmatic "$LOG"; do [ -f "$f" ] || ko "manca $f"; done
[ "$(attrs "$LOG")" = "root:root 644" ] && ok "$LOG root 0644" || ko "$LOG $(attrs "$LOG")"
[ -f "$LR_SRC" ] || die "manca il modello $LR_SRC"
[ ! -e "$LR" ] || cmp -s "$LR" "$LR_SRC" || die "$LR esiste ed è diverso dal modello: da valutare a mano"
[ ! -e "$LOG.1" ] || die "$LOG.1 esiste già: rotazione da valutare a mano"
[ "$(systemctl is-enabled borgmatic.timer)" = disabled ] && ok "borgmatic.timer disabilitato" || ko "borgmatic.timer non disabilitato"
if pgrep -x borg >/dev/null || pgrep -x borgmatic >/dev/null; then ko "borg/borgmatic in esecuzione"; fi
[ "$bad" -eq 0 ] || die "controlli non superati: nessuna modifica"

echo "== 1. ROTAZIONE"
install -o root -g root -m 0644 "$LR_SRC" "$LR"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) file-$LR created" >> "$MANIFEST"
out=$(logrotate -d "$LR" 2>&1) || true
grep -qiE '^error' <<<"$out" && { echo "$out" | tail -5; ko "logrotate -d segnala errori"; } || ok "logrotate -d $LR senza errori"

echo "== 2. PROVA REALE DELLA ROTAZIONE"
logrotate -f "$LR"
[ -f "$LOG.1" ] && grep -q 'Creating archive at' "$LOG.1" && ok "log ruotato in $LOG.1 (non compresso, con l'archivio)" || ko "rotazione non riuscita"
[ -f "$LOG" ] && [ ! -s "$LOG" ] && [ "$(attrs "$LOG")" = "root:root 644" ] && ok "nuovo $LOG vuoto, root 0644" || ko "$LOG dopo la rotazione: $(attrs "$LOG" 2>/dev/null)"
q=$(runuser -u "$ADMIN" -- "$OPS/bin/quick-check" 2>&1 | grep -E 'archivio Borg|nessun archivio' || true)
echo "  quick-check: $q"
grep -q 'OK .*archivio Borg' <<<"$q" && ok "quick-check trova l'archivio nel log ruotato" || ko "quick-check non trova l'archivio dopo la rotazione"

echo "== 3. SECONDO BACKUP E PROVA DI RIPRISTINO (ripresa di passo10-backup.sh)"
rc=0; bash "$P10" || rc=$?
[ "$rc" -eq 0 ] && ok "passo10-backup.sh (ripresa): esito 0" || ko "passo10-backup.sh (ripresa): esito $rc"
grep -q 'Creating archive at' "$LOG" && ok "il nuovo backup scrive nel nuovo $LOG" || ko "nessun archivio nel nuovo $LOG"
q=$(runuser -u "$ADMIN" -- "$OPS/bin/quick-check" 2>&1 | sed -n '/^Backup/,/^Manutenzione/p' | grep -v '^Manutenzione' || true)
echo "$q" | sed 's/^/  /'
echo "ESITO PASSO 10B=$bad"
exit $bad
