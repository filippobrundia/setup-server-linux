#!/bin/bash
# Passo 10.1–10.2 — backup locale Borg con borgmatic (decisioni ereditate del 2026-09-24) e prova di ripristino.
#
# Uso (terminale vero):
#   sudo bash /srv/ops/docs/bootstrap/passo10-backup.sh --dry-run   # controlli e validazione, nessuna scrittura di sistema
#   sudo bash /srv/ops/docs/bootstrap/passo10-backup.sh             # repository, config, cron, primo backup, ripristino
#   sudo bash /srv/ops/docs/bootstrap/passo10-backup.sh --rollback  # toglie cron, script e config; il repository resta
#
# - Repository locale NON cifrato in BORG_REPO di host.conf, se vuoto <DATA_MOUNT>/dati/backup/borg-repo-plain
#   (borg init solo su cartella assente o vuota). A fine passo BORG_REPO va scritto in host.conf (sezione 10.1).
# - /etc/borgmatic/config.yaml dal modello maint/templates/borgmatic-config.yaml: le sorgenti attive del modello,
#   /etc/docker/daemon.json se Docker è configurato (riga commentata del modello), /root/.borgmatic solo se esiste
#   (in borgmatic 2.0 è un percorso deprecato); esclusioni, retention, compressione e controlli del modello.
# - Solo la base SENZA servizi: con CONTAINERS o SQLITE_SNAPSHOTS in host.conf lo script si ferma, perché dati,
#   esclusioni dei segreti e snapshot dei servizi vanno scritti a mano (sezioni 8.2 e 10.1).
# - Un solo scheduler: /etc/cron.d/borgmatic (03:00 UTC) dal modello; borgmatic.timer resta disabilitato.
# - Primo backup lanciato come lo lancerà il cron (stesso script, stesso log /var/log/borgmatic.log).
# - Prova di ripristino con "borgmatic extract" in /var/tmp/ops-restore-* (mai sopra gli originali), confronto di
#   contenuto e di proprietario/permessi con gli originali, poi la cartella temporanea viene rimossa.
# - Copia remota (10.3) NON configurata qui: destinazione e credenziali mancano.
set -euo pipefail

CONF=/etc/borgmatic/config.yaml
RUNNER=/usr/local/bin/run-borgmatic.sh
CRON=/etc/cron.d/borgmatic
LOG=/var/log/borgmatic.log
STATE_DIR=/var/lib/ops-bootstrap
MANIFEST=$STATE_DIR/passo10-backup.manifest
# shellcheck source=passi-comune.sh
. "$(dirname "$0")/passi-comune.sh"
TEMPLATE=$TEMPLATES/borgmatic-config.yaml
RUNNER_SRC=$TEMPLATES/run-borgmatic.sh
CRON_SRC=$TEMPLATES/cron-borgmatic

MODE=apply
case "${1:-}" in "") ;; --dry-run) MODE=dry ;; --rollback) MODE=rollback ;; *) echo "argomento sconosciuto: $1" >&2; exit 2 ;; esac
die() { echo "ERRORE: $*" >&2; exit 1; }
ok() { echo "ok  $*"; }
ko() { echo "KO  $*"; bad=1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
attrs() { stat -c '%U:%G %a' -- "$1"; }
rec() { echo "$(now) $*" >> "$MANIFEST"; }
last() { [ -f "$MANIFEST" ] && awk -v k="$1" '$2==k{s=$3} END{print s}' "$MANIFEST"; }
[ "$(id -u)" -eq 0 ] || die "va eseguito con sudo"
export LC_ALL=C.UTF-8
load_host_conf
need DATA_MOUNT "punto di montaggio del disco dati (sezione 0)"
BACKUP_DIR=$DATA_MOUNT/dati/backup
REPO=${BORG_REPO:-$BACKUP_DIR/borg-repo-plain}
# sorgenti attive del modello (righe "  - /percorso", commenti esclusi), senza /root/.borgmatic (aggiunto solo se esiste)
mapfile -t SOURCES < <(sed -n '/^source_directories:/,/^[a-z_]*:/{s/^  - \(\/[^ #]*\).*/\1/p}' "$TEMPLATE" | grep -vx /root/.borgmatic)
[ "${#SOURCES[@]}" -gt 0 ] || die "nessuna sorgente letta dal modello $TEMPLATE"
[ -e /etc/docker/daemon.json ] && SOURCES+=(/etc/docker/daemon.json)
if [ -e "$STATE_DIR" ]; then [ "$(attrs "$STATE_DIR")" = "root:root 700" ] || die "$STATE_DIR non è root 0700"; fi
if [ -e "$MANIFEST" ]; then [ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] && [ "$(attrs "$MANIFEST")" = "root:root 600" ] || die "$MANIFEST non è root 0600"; fi

if [ "$MODE" = rollback ]; then
  echo "== ROLLBACK"
  [ -f "$MANIFEST" ] || die "nessun manifest: questo script non ha installato nulla"
  for f in "$CRON" "$RUNNER" "$CONF"; do
    if [ "$(last "file-$f")" = created ] && [ -f "$f" ]; then mv -f -- "$f" "$f.rollback-$(date -u +%F)"; rec "file-$f" removed; echo "spostato $f in $f.rollback-*"; fi
  done
  echo "lasciati: repository $REPO e $LOG (cancellare un backup richiede il consenso del proprietario)"
  exit 0
fi

# ---- PRECHECK
echo "== PRECHECK"
bad=0
echo "  $(borg --version), borgmatic $(borgmatic --version)"
[ "$(systemctl is-enabled borgmatic.timer 2>/dev/null)" = disabled ] && ! systemctl is-active --quiet borgmatic.timer \
  && ok "borgmatic.timer disabilitato e inattivo" || ko "borgmatic.timer non disabilitato/inattivo"
[ -z "$CONTAINERS" ] && [ "${SQLITE_SNAPSHOTS:-0}" = 0 ] \
  || die "host.conf indica servizi (CONTAINERS/SQLITE_SNAPSHOTS): questo script copre solo la base senza servizi"
[ "$(attrs "$BACKUP_DIR")" = "root:root 750" ] && ok "$BACKUP_DIR root 0750" || ko "$BACKUP_DIR $(attrs "$BACKUP_DIR")"
fsb=$(findmnt -n -o TARGET --target "$BACKUP_DIR")
[ "$fsb" = / ] && echo "  nota: backup locale sul filesystem radice (layout a disco unico, sezione 0)" || ok "backup locale su $fsb"
echo "  repository: $REPO; spazio libero: $(df -h --output=avail "$BACKUP_DIR" | tail -1 | tr -d ' ')"
resume=0; [ -f "$MANIFEST" ] && resume=1
if [ "$resume" = 0 ]; then
  for f in "$CONF" "$RUNNER" "$CRON"; do [ ! -e "$f" ] || ko "$f esiste già: stato da valutare a mano"; done
  if [ -e "$REPO" ]; then [ -d "$REPO" ] && [ -z "$(ls -A "$REPO")" ] || ko "$REPO esiste e non è una cartella vuota"; fi
else
  echo "nota: ripresa di un'esecuzione precedente (manifest presente)"
fi
for p in "${SOURCES[@]}"; do [ -e "$p" ] || [ "$p" = /etc/borgmatic ] || ko "sorgente mancante: $p"; done
EXTRA=(); if [ -e /root/.borgmatic ]; then EXTRA=(/root/.borgmatic); echo "  /root/.borgmatic esiste: incluso"; else echo "  /root/.borgmatic assente (deprecato in borgmatic 2.0): non incluso"; fi
grep -qx '0 3 \* \* \* root /usr/local/bin/run-borgmatic.sh >> /var/log/borgmatic.log 2>&1' "$CRON_SRC" || ko "modello cron inatteso"
if pgrep -x borg >/dev/null || pgrep -x borgmatic >/dev/null; then ko "borg/borgmatic già in esecuzione"; fi

# configurazione generata dal modello e validata prima di installarla
TMPC=$(mktemp --suffix=.yaml); TMPD=""; trap 'rm -f "$TMPC"; [ -n "$TMPD" ] && rm -rf -- "$TMPD"' EXIT
{
  echo "# /etc/borgmatic/config.yaml — generato da docs/bootstrap/passo10-backup.sh dal modello"
  echo "# maint/templates/borgmatic-config.yaml (decisioni ereditate del 2026-09-24). Nessun segreto qui dentro."
  echo "repositories:"; echo "  - path: $REPO"
  echo "source_directories:"; for p in "${SOURCES[@]}" "${EXTRA[@]}"; do echo "  - $p"; done
  sed -n '/^exclude_patterns:/,$p' "$TEMPLATE" | grep -vE '^\s*#|^#'
} > "$TMPC"
grep -q '^keep_monthly: 6$' "$TMPC" && grep -q "^compression: zstd,8$" "$TMPC" || ko "parti del modello mancanti nella configurazione generata"
borgmatic config validate -c "$TMPC" >/dev/null && ok "configurazione generata valida (borgmatic config validate)" || ko "configurazione non valida"
echo "  configurazione:"; sed 's/^/    /' "$TMPC"
[ "$bad" -eq 0 ] || die "controlli non superati: nessuna modifica"
[ "$MODE" = dry ] && { echo "== DRY-RUN: nessuna scrittura di sistema (configurazione solo in un file temporaneo, rimosso)"; exit 0; }

# ---- MODIFICA
echo "== MODIFICA"
install -d -o root -g root -m 0700 -- "$STATE_DIR"; ( umask 077; : >> "$MANIFEST" ); chmod 0600 -- "$MANIFEST"
rec run start
if [ ! -e "$REPO/config" ]; then
  install -d -o root -g root -m 0700 -- "$REPO"
  borg init --encryption=none "$REPO"; rec "repo-$REPO" created
fi
if [ ! -e "$CONF" ]; then
  install -d -o root -g root -m 0750 "$(dirname "$CONF")"
  install -o root -g root -m 0600 "$TMPC" "$CONF"; rec "file-$CONF" created
fi
if [ ! -e "$RUNNER" ]; then install -o root -g root -m 0750 "$RUNNER_SRC" "$RUNNER"; rec "file-$RUNNER" created; fi
borgmatic config validate -c "$CONF" >/dev/null && ok "$CONF valido" || die "$CONF non valido: cron NON installato"
# primo backup esattamente come dal cron (stesso comando e stesso log), prima di installare il cron
echo "  primo backup (log: $LOG) ..."
brc=0; /usr/local/bin/run-borgmatic.sh >> "$LOG" 2>&1 || brc=$?
rec run "first-backup-exit $brc"
[ "$brc" -eq 0 ] || { tail -20 "$LOG" >&2; die "primo backup fallito (codice $brc): cron NON installato"; }
if [ ! -e "$CRON" ]; then install -o root -g root -m 0644 "$CRON_SRC" "$CRON"; rec "file-$CRON" created; fi

# ---- VERIFY
echo "== VERIFY"
bad=0
borg info "$REPO" | grep -E 'Encrypted|Repository ID|Unique chunks|All archives' | sed 's/^/  /' || true
borg info "$REPO" | grep -q '^Encrypted: No' && ok "repository non cifrato (decisione ereditata)" || ko "cifratura del repository inattesa"
mapfile -t ARCH < <(borg list --short "$REPO")
[ "${#ARCH[@]}" -ge 1 ] && ok "archivi: ${#ARCH[*]} (ultimo ${ARCH[-1]})" || ko "nessun archivio"
grep -E 'Creating archive at|Successfully ran configuration file' "$LOG" | tail -2 | sed 's/^/  log: /'
grep -qE 'CRITICAL|An error occurred' <(tail -n +"$(grep -n 'Creating archive at' "$LOG" | tail -1 | cut -d: -f1)" "$LOG") \
  && ko "errori nel log dell'ultimo backup" || ok "log dell'ultimo backup senza errori"
[ "$(attrs "$LOG")" = "root:root 644" ] && ok "$LOG leggibile dall'amministratore (root 0644)" || echo "  nota: $LOG $(attrs "$LOG")"
for pw in "$CONF=600" "$RUNNER=750" "$CRON=644"; do
  p=${pw%=*}; [ "$(attrs "$p")" = "root:root ${pw#*=}" ] && ok "$p root:root ${pw#*=}" || ko "$p $(attrs "$p") (atteso root:root ${pw#*=})"
done
cmp -s "$CRON" "$CRON_SRC" && ok "$CRON = modello (03:00 UTC)" || ko "$CRON diverso dal modello"
cmp -s "$RUNNER" "$RUNNER_SRC" && ok "$RUNNER = modello" || ko "$RUNNER diverso dal modello"
[ "$(systemctl is-enabled borgmatic.timer 2>/dev/null)" = disabled ] && ok "borgmatic.timer ancora disabilitato (scheduler unico: cron)" || ko "borgmatic.timer non disabilitato"

# prova di ripristino in una cartella temporanea, mai sopra gli originali
TMPD=$(mktemp -d /var/tmp/ops-restore-XXXXXX); chmod 0700 "$TMPD"
borgmatic -c "$CONF" extract --archive latest --destination "$TMPD" >/dev/null && ok "borgmatic extract in $TMPD" || ko "borgmatic extract fallito"
T0=$(date -d "$(sed -E "s/^$HOST-//; s/T/ /; s/\..*//" <<<"${ARCH[-1]}")" +%s)
nd=0; nl=0; nm=0
for p in "${SOURCES[@]}" "${EXTRA[@]}"; do
  [ -e "$TMPD$p" ] || { ko "manca nel ripristino: $p"; continue; }
  d=$(diff -rq --no-dereference "$p" "$TMPD$p" 2>&1 || true)
  if [ -n "$d" ]; then
    # una differenza è accettabile solo se l'originale è stato modificato dopo l'inizio del backup
    while read -r line; do
      f=$(sed -E 's/^Files (.+) and .+ differ$/\1/; s/^Only in ([^:]+): (.+)$/\1\/\2/' <<<"$line")
      case "$f" in "$TMPD"*) f=${f#"$TMPD"} ;; esac
      if [ -e "$f" ] && [ "$(stat -c %Y -- "$f")" -ge "$T0" ]; then nl=$((nl+1)); echo "  modificato dopo il backup: $f"
      else nd=$((nd+1)); echo "  DIFFERENZA: $line"; fi
    done <<<"$d"
  fi
  m=$(diff <(cd "$p" 2>/dev/null && find . -printf '%P %U:%G %m %y\n' | sort || stat -c '. %U:%G %a %F' "$p") \
           <(cd "$TMPD$p" 2>/dev/null && find . -printf '%P %U:%G %m %y\n' | sort || stat -c '. %U:%G %a %F' "$TMPD$p") | grep -c '^[<>]' || true)
  [ "$m" -eq 0 ] || { nm=$((nm+m)); echo "  proprietario/permessi diversi in $p: $m righe (contano anche file creati dopo il backup)"; }
done
[ "$nd" -eq 0 ] && ok "file ripristinati identici agli originali (${#SOURCES[@]} sorgenti; modificati dopo il backup: $nl)" || ko "$nd differenze non spiegate"
[ "$nm" -eq 0 ] && ok "proprietario, gruppo e permessi ripristinati uguali agli originali" || echo "  nota: $nm differenze di proprietario/permessi da leggere sopra"
rm -rf -- "$TMPD"; TMPD=""; ok "cartella di ripristino temporanea rimossa"

# quick-check come lo vedrà l'amministratore, con BORG_REPO impostato in una copia temporanea di host.conf
Q=$(mktemp -d); cp "$HOSTCONF" "$Q/"; sed -i "s|^BORG_REPO=\"\"|BORG_REPO=\"$REPO\"|" "$Q/host.conf"; chmod -R a+rX "$Q"
runuser -u "$ADMIN" -- env OPS_DIR="$Q" "$OPS/bin/quick-check" 2>&1 | sed -n '/^Backup/,/^[A-Z]/p' | sed 's/^/  /' || true
rm -rf -- "$Q"
[ "$(hc_get BORG_REPO)" = "$REPO" ] || echo "  DA FARE: BORG_REPO=\"$REPO\" in $HOSTCONF (sezione 10.1), con commit"
echo "  copia remota (10.3): NON configurata da questo script (destinazione e credenziali dal proprietario)"
echo "ESITO PASSO 10=$bad"
exit $bad
