#!/bin/bash
# Passo 6 — pacchetti di base mancanti (tabella della sezione 6 della checklist).
#
# Uso (terminale vero, non la modalità ! di Claude Code):
#   sudo bash /srv/ops/docs/bootstrap/passo6-pacchetti.sh            # PRECHECK + MODIFICA + VERIFY
#   sudo bash /srv/ops/docs/bootstrap/passo6-pacchetti.sh --dry-run  # solo PRECHECK e simulazione APT
#   sudo bash /srv/ops/docs/bootstrap/passo6-pacchetti.sh --rollback # rimuove (remove, non purge) i pacchetti
#                                                                    # installati da questo script
#
# borgmatic: il postinst abilita e avvia borgmatic.timer (borgmatic.service è statico e non viene avviato).
# Per evitare qualunque avvio prima della configurazione (passo 10) il timer viene MASCHERATO prima
# dell'installazione: deb-systemd-helper non toglie un mascheramento dell'amministratore e deb-systemd-invoke non
# avvia un'unità che risulta "masked" (verificato su Ubuntu 26.04 con borgmatic 2.0, simulazione del postinst). Dopo
# l'installazione il timer viene smascherato e disabilitato (stato atteso del 10.2), senza essere mai partito.
# Un mascheramento preesistente non viene mai tolto. Se APT fallisce: nessuna disinstallazione automatica, stato
# reale riconciliato nel manifest, mascheramento mantenuto, uscita con il codice di APT; si riprende rilanciando.
# fail2ban: parte con la configurazione del pacchetto; il VERIFY legge la configurazione EFFETTIVA dal demone.
# btrfs-progs solo se il disco dati (DATA_MOUNT di host.conf) è btrfs.
# APT: nessuna rimozione e nessun aggiornamento ammessi (--no-remove --no-upgrade), origini solo la release Ubuntu in
# uso (/etc/os-release); blocchi APT rispettati
# (DPkg::Lock::Timeout). Manifest: /var/lib/ops-bootstrap/passo6-pacchetti.manifest (root 0600). Ripetibile.
set -euo pipefail

PKGS_ALL=(git curl ca-certificates gnupg jq tmux htop btop neovim net-tools acl sqlite3 ufw fail2ban
          unattended-upgrades borgbackup borgmatic rclone fuse3 sysstat)
MANIFEST_DIR=/var/lib/ops-bootstrap
MANIFEST=$MANIFEST_DIR/passo6-pacchetti.manifest
TIMER=borgmatic.timer
MASK=/etc/systemd/system/$TIMER
APT_OPTS=(-o DPkg::Lock::Timeout=600)
# shellcheck source=passi-comune.sh
. "$(dirname "$0")/passi-comune.sh"

MODE=apply
case "${1:-}" in
  "") ;;
  --dry-run) MODE=dry ;;
  --rollback) MODE=rollback ;;
  *) echo "argomento sconosciuto: $1" >&2; exit 2 ;;
esac

die() { echo "ERRORE: $*" >&2; exit 1; }
attrs() { stat -c '%U:%G %a' -- "$1"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
missing() { dpkg-query -W -f='${Status} ${Package}\n' "${PKGS_ALL[@]}" 2>&1 | grep -v '^install ok installed' || true; }
is_our_mask() { [ -L "$MASK" ] && [ "$(readlink -- "$MASK")" = /dev/null ]; }

# Manifest, righe "<data> <evento> …": "pkg-before <pacchetto> <stato>" (prima di APT), "pkg <pacchetto> <stato>"
# (stato reale dopo APT o dopo il rollback), "mask <created|preexisting|kept-apt-failed|removed-disabled|removed>",
# "run <start|apt-exit N|rollback-exit N>". Stati: installed, absent, half:<stato dpkg>. Vale l'ultima riga.
rec() { echo "$(now) $*" >> "$MANIFEST"; }
pkg_state() {
  local s; s=$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true)
  case "$s" in
    "install ok installed") echo installed ;;
    ""|*" not-installed"|*" config-files") echo absent ;;
    *) echo "half:${s##* }" ;;
  esac
}
last_mask() { [ -f "$MANIFEST" ] && awk '$2=="mask"{s=$3} END{print s}' "$MANIFEST"; }
# mascheramento creato da questo script (non uno preesistente) e ancora presente
mask_is_ours() { is_our_mask && case "$(last_mask)" in created|kept-apt-failed) true ;; *) false ;; esac; }
# pacchetti la cui ultima riga è "pkg-before" (APT interrotto o fallito) o uno stato parziale (poi completato,
# per esempio con dpkg --configure -a): si registra lo stato reale
reconcile() {
  local p
  for p in $(awk '$2=="pkg-before"||$2=="pkg"{last[$3]=$2; st[$3]=$4}
                  END{for (p in last) if (last[p]=="pkg-before" || st[p] ~ /^half:/) print p}' "$MANIFEST" | sort); do
    rec pkg "$p" "$(pkg_state "$p")"
  done
}
# pacchetti introdotti da questo script il cui ULTIMO stato registrato è installato o parziale
rollback_candidates() {
  awk '$2=="pkg"{st[$3]=$4} END{for (p in st) if (st[p]=="installed" || st[p] ~ /^half:/) print p}' "$MANIFEST" | sort
}
dpkg_audit() { dpkg --audit 2>&1 || true; }

[ "$(id -u)" -eq 0 ] || die "va eseguito con sudo"
export LC_ALL=C.UTF-8
load_host_conf
load_os_release
ORIGIN_RE=$UBUNTU_ORIGIN_RE
need DATA_MOUNT "punto di montaggio del disco dati (sezione 0)"
[ "$(findmnt -n -o FSTYPE --target "$DATA_MOUNT")" = btrfs ] && PKGS_ALL+=(btrfs-progs)

check_manifest() {
  if [ -e "$MANIFEST_DIR" ] || [ -L "$MANIFEST_DIR" ]; then
    [ -d "$MANIFEST_DIR" ] && [ ! -L "$MANIFEST_DIR" ] || die "$MANIFEST_DIR non è una cartella reale"
    [ "$(attrs "$MANIFEST_DIR")" = "root:root 700" ] || die "$MANIFEST_DIR: $(attrs "$MANIFEST_DIR") (atteso root:root 700)"
  fi
  if [ -e "$MANIFEST" ] || [ -L "$MANIFEST" ]; then
    [ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || die "$MANIFEST non è un file regolare"
    [ "$(attrs "$MANIFEST")" = "root:root 600" ] || die "$MANIFEST: $(attrs "$MANIFEST") (atteso root:root 600)"
  fi
}

# ---- ROLLBACK: remove (non purge) dei soli pacchetti che il manifest dà come installati da questo script.
if [ "$MODE" = rollback ]; then
  echo "== ROLLBACK"
  check_manifest
  [ -f "$MANIFEST" ] || { echo "nessun manifest: questo script non ha installato nulla"; exit 0; }
  reconcile
  mapfile -t P < <(rollback_candidates)
  rrc=0
  if [ "${#P[@]}" -eq 0 ]; then
    echo "nessun pacchetto installato da questo script secondo l'ultimo stato registrato"
  else
    echo "da rimuovere (ultimo stato registrato): ${P[*]}"
    SIM=$(apt-get -s "${APT_OPTS[@]}" remove "${P[@]}")
    extra=$(grep '^Remv ' <<<"$SIM" | awk '{print $2}' | grep -vxF -f <(printf '%s\n' "${P[@]}") || true)
    [ -z "$extra" ] || die "la rimozione toccherebbe anche pacchetti non installati da questo script: $extra"
    summary=$(grep -E '^[0-9]+ upgraded, [0-9]+ newly installed' <<<"$SIM") || die "simulazione APT illeggibile"
    read -r up _ new _ <<<"$summary"
    [ "$up" -eq 0 ] && [ "$new" -eq 0 ] || die "la rimozione installerebbe o aggiornerebbe pacchetti: $summary"
    echo "simulazione: $summary"
    apt-get "${APT_OPTS[@]}" remove -y "${P[@]}" || rrc=$?
    for p in "${P[@]}"; do rec pkg "$p" "$(pkg_state "$p")"; done
    rec run "rollback-exit $rrc"
  fi
  # solo il mascheramento creato da questo script; con borgmatic ancora presente il timer resta disabilitato
  if mask_is_ours; then
    systemctl unmask "$TIMER"
    if [ "$(pkg_state borgmatic)" = absent ]; then rec mask removed
    else systemctl disable "$TIMER" 2>&1 | sed 's/^/  /'; rec mask removed-disabled; fi
    echo "tolto il mascheramento di $TIMER creato da questo script"
  elif is_our_mask; then
    echo "mascheramento di $TIMER preesistente: lasciato"
  fi
  [ "$rrc" -eq 0 ] || { echo "ERRORE: apt-get remove terminato con codice $rrc; stato reale registrato nel manifest" >&2; exit "$rrc"; }
  echo "configurazioni (conffile) e /var/lib/fail2ban conservati: rimozione completa solo con purge, a mano"
  exit 0
fi

# ---- PRECHECK (nessuna scrittura)
echo "== PRECHECK"
check_manifest
# Aggiornamenti automatici: apt-daily-upgrade 06:00 UTC + fino a 60 min (anche in recupero dopo un avvio,
# Persistent=true); apt-daily scarica in un momento casuale (06:00/18:00 + fino a 12 h): lo copre DPkg::Lock::Timeout.
# Backup 03:00–04:10: non ancora attivi al passo 6 (borgmatic non configurato).
h=$(date -u +%H)
[ "$h" != 06 ] || die "06:00–07:00 UTC: finestra degli aggiornamenti automatici, riprovare dopo le 07:00 UTC"
if systemctl is-active --quiet apt-daily-upgrade.service; then
  die "apt-daily-upgrade.service in corso (aggiornamenti automatici): riprovare quando è terminato"
fi
systemctl is-active --quiet apt-daily.service && echo "nota: apt-daily.service in corso, APT attenderà il blocco (max 600 s)"
[ ! -e /etc/cron.d/borgmatic ] || echo "nota: /etc/cron.d/borgmatic esiste già (inatteso al passo 6)"

mapfile -t TODO < <(missing | awk '{print $NF}')
echo "mancanti: ${TODO[*]:-nessuno}"

# Installazione precedente interrotta: dpkg va completato prima di qualunque altra operazione APT.
audit=$(dpkg_audit)
[ -z "$audit" ] || die "dpkg segnala pacchetti non configurati (installazione precedente interrotta):
$audit
Ripresa: sudo dpkg --configure -a (l'eventuale mascheramento di $TIMER resta), poi rilanciare questo script."

# Stato iniziale del timer: assente, mascherato da una precedente esecuzione (ripresa) o mascherato da altri.
tstate=$(systemctl is-enabled "$TIMER" 2>/dev/null || true)
MASK_PRE=
if [ -e "$MASK" ] || [ -L "$MASK" ]; then
  is_our_mask || die "$MASK esiste e non è un mascheramento: da valutare a mano"
  if mask_is_ours; then echo "nota: $TIMER mascherato da una precedente esecuzione di questo script (ripresa)"
  else MASK_PRE=1; echo "nota: mascheramento PREESISTENTE di $TIMER: sarà lasciato com'è"; fi
fi
echo "$TIMER: ${tstate:-non installato}"
if [ -d /etc/borgmatic ] || [ -d /etc/borgmatic.d ]; then
  ls -la /etc/borgmatic /etc/borgmatic.d 2>/dev/null
  echo "nota: esiste già una configurazione borgmatic (il postinst ne genererebbe una .dpkg-dist migrata)"
fi
# fail2ban: un'eventuale configurazione locale preesistente cambierebbe l'effetto sul login SSH.
if [ -d /etc/fail2ban ]; then
  local_cfg=$(find /etc/fail2ban -name '*.local' -o -path '*/jail.d/*' ! -name defaults-debian.conf | sort)
  [ -z "$local_cfg" ] || { echo "nota: configurazioni locali fail2ban presenti:"; echo "$local_cfg"; }
fi

FAILED_BEFORE=$(systemctl --failed --plain --no-legend | awk '{print $1}' | sort)
echo "unità in errore prima: ${FAILED_BEFORE:-nessuna}"
echo "sessioni SSH aperte (un ban fail2ban le bloccherebbe tutte per lo stesso IP):"
# "who" è vuoto su Ubuntu 26.04 (manca /run/utmp): connessioni TCP stabilite sulla porta 22
ss -tnH state established '( sport = :22 )' | awk '{print "  " $4}'

if [ "${#TODO[@]}" -gt 0 ]; then
  SIM=$(apt-get -s "${APT_OPTS[@]}" install "${TODO[@]}")
  summary=$(grep -E '^[0-9]+ upgraded, [0-9]+ newly installed, [0-9]+ to remove' <<<"$SIM") || die "simulazione APT illeggibile"
  echo "simulazione: $summary"
  read -r up _ new _ _ rem _ <<<"$summary"
  [ "$up" -eq 0 ] && [ "$rem" -eq 0 ] || die "la simulazione prevede aggiornamenti o rimozioni: fermarsi"
  bad_origin=$(grep '^Inst ' <<<"$SIM" | grep -vE "$ORIGIN_RE" || true)
  [ -z "$bad_origin" ] || die "pacchetti da origini diverse da Ubuntu $VERSION_ID:"$'\n'"$bad_origin"
  mapfile -t NEW < <(grep '^Inst ' <<<"$SIM" | awk '{print $2}')
  echo "pacchetti nuovi: ${#NEW[@]}"
fi
[ "$MODE" = dry ] && { echo "== DRY-RUN: nessuna scrittura"; exit 0; }

# ---- MODIFICA
echo "== MODIFICA"
START=$(date '+%Y-%m-%d %H:%M:%S')
install -d -o root -g root -m 0700 -- "$MANIFEST_DIR"
( umask 077; : >> "$MANIFEST" ); chown root:root -- "$MANIFEST"; chmod 0600 -- "$MANIFEST"
check_manifest
reconcile   # esecuzione precedente interrotta durante APT
rec run start
[ -z "$MASK_PRE" ] || [ "$(last_mask)" = preexisting ] || rec mask preexisting

if [ "${#TODO[@]}" -gt 0 ]; then
  # 1) borgmatic.timer mascherato PRIMA dell'installazione: non potrà essere avviato dal postinst.
  if [ -n "$MASK_PRE" ] || mask_is_ours; then
    :
  elif [ "$(pkg_state borgmatic)" = installed ]; then
    echo "borgmatic già installato: nessun mascheramento"
  else
    systemctl mask "$TIMER"
    is_our_mask || die "mascheramento di $TIMER non riuscito: nessuna installazione eseguita"
    rec mask created
  fi
  # 2) stato iniziale registrato, poi installazione: --no-remove e --no-upgrade fanno fallire APT se comparisse
  #    una rimozione o l'aggiornamento di un pacchetto già installato dopo la simulazione.
  for p in "${NEW[@]}"; do rec pkg-before "$p" "$(pkg_state "$p")"; done
  arc=0
  apt-get "${APT_OPTS[@]}" install -y --no-remove --no-upgrade "${TODO[@]}" || arc=$?
  # 3) riconciliazione dello stato reale, anche dopo un'installazione parziale
  reconcile
  rec run "apt-exit $arc"
  if [ "$arc" -ne 0 ]; then
    mask_is_ours && rec mask kept-apt-failed
    echo "ERRORE: apt-get install terminato con codice $arc. Stato reale dei pacchetti:" >&2
    for p in "${NEW[@]}"; do echo "  $p $(pkg_state "$p")"; done >&2
    mask_is_ours && echo "$TIMER resta MASCHERATO (nessun backup prima della configurazione)." >&2
    echo "Nessuna disinstallazione automatica. Ripresa: capire la causa dall'output di APT; se dpkg è stato" >&2
    echo "interrotto: sudo dpkg --configure -a; poi rilanciare questo script (installa solo ciò che manca e" >&2
    echo "toglie il mascheramento a installazione completa). Per annullare invece: --rollback." >&2
    exit "$arc"
  fi
else
  echo "nulla da installare"
fi
# 4) il timer non è mai partito: si toglie il SOLO mascheramento creato da questo script e lo si lascia
#    disabilitato (stato del 10.2). Vale anche in ripresa, quando non restano pacchetti da installare.
if mask_is_ours; then
  if [ "$(pkg_state borgmatic)" = installed ] && [ -z "$(dpkg_audit)" ]; then
    systemctl is-active --quiet "$TIMER" && die "$TIMER risulta attivo nonostante il mascheramento: verificare"
    systemctl unmask "$TIMER"
    systemctl disable "$TIMER" 2>&1 | sed 's/^/  /'
    rec mask removed-disabled
  else
    echo "borgmatic non installato completamente: $TIMER resta mascherato"
  fi
elif [ -n "$MASK_PRE" ]; then
  echo "mascheramento preesistente di $TIMER lasciato com'è"
fi

# ---- VERIFY
echo "== VERIFY"
rc=0
ok() { echo "ok  $*"; }
ko() { echo "KO  $*"; rc=1; }

m=$(missing); [ -z "$m" ] && ok "controllo dpkg-query del passo 6: nessun pacchetto mancante" || ko "mancano ancora: $m"

# borgmatic: mai avviato
e=$(systemctl is-enabled "$TIMER" 2>/dev/null || true); a=$(systemctl is-active "$TIMER" 2>/dev/null || true)
want=disabled; [ -z "$MASK_PRE" ] || want=masked   # un mascheramento preesistente resta
[ "$e" = "$want" ] && ok "$TIMER $e" || ko "$TIMER is-enabled=$e (atteso $want)"
[ "$a" = inactive ] && ok "$TIMER inactive" || ko "$TIMER is-active=$a (atteso inactive)"
mask_is_ours && ko "$MASK creato da questo script ancora presente" || true
ts=$(systemctl show -P ExecMainStartTimestampMonotonic borgmatic.service)
[ "${ts:-0}" = 0 ] && ok "borgmatic.service mai eseguito in questo avvio" || ko "borgmatic.service eseguito (monotonic=$ts)"
j=$(journalctl -q --no-pager -u borgmatic.service -u "$TIMER" --since "$START" | grep -vi 'unit.*mask\|reload' || true)
[ -z "$j" ] && ok "journal di borgmatic vuoto dall'inizio dell'intervento" || { ko "eventi borgmatic nel journal:"; echo "$j"; }

# fail2ban: configurazione EFFETTIVA letta dal demone in esecuzione
if systemctl is-active --quiet fail2ban && fail2ban-client ping >/dev/null 2>&1; then
  ok "fail2ban attivo ($(systemctl is-enabled fail2ban) all'avvio)"
  echo "  jail:      $(fail2ban-client status | sed -n 's/.*Jail list:\s*//p')"
  for k in maxretry findtime bantime ignoreself ignoreip journalmatch actions; do
    printf '  %-12s %s\n' "$k" "$(fail2ban-client get sshd "$k" 2>&1 | tr '\n' ' ' | sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<IP>/g')"
  done
  echo "  backend:   $(fail2ban-client -d 2>/dev/null | grep -F "['add', 'sshd'" || echo '?')"
  echo "  porte:     $(fail2ban-client -d 2>/dev/null | grep -oE "\['port', '[^']*'\]" | sort -u | tr '\n' ' ')"
  banned=$(fail2ban-client get sshd banned 2>/dev/null || echo '?')
  [ "$banned" = "[]" ] && ok "nessun IP bandito" || ko "IP banditi: $banned"
  # il filtro deve leggere il journal reale di ssh.service (sshd-session di OpenSSH 10.2)
  fr=$(fail2ban-regex 'systemd-journal' 'sshd[journalmatch="_SYSTEMD_UNIT=ssh.service + _COMM=sshd"]' 2>&1 | grep -E '^Lines:' || true)
  [ -n "$fr" ] && ok "fail2ban-regex sul journal: $fr" || ko "fail2ban-regex non ha letto il journal"
  nft list table inet f2b-table >/dev/null 2>&1 && echo "  tabella nftables inet f2b-table presente" \
    || echo "  tabella nftables inet f2b-table non ancora creata (normale prima del primo ban)"
else
  ko "fail2ban non attivo: systemctl status fail2ban"
fi

FAILED_AFTER=$(systemctl --failed --plain --no-legend | awk '{print $1}' | sort)
new_failed=$(comm -13 <(echo "$FAILED_BEFORE") <(echo "$FAILED_AFTER") | sed '/^$/d')
[ -z "$new_failed" ] && ok "nessuna nuova unità in errore" || ko "nuove unità in errore: $new_failed"
echo "  ssh: socket $(systemctl is-active ssh.socket || true), servizio $(systemctl is-active ssh.service || true)"
echo "manifest $MANIFEST ($(attrs "$MANIFEST")): $(rollback_candidates | wc -l) pacchetti installati da questo script"
echo "ultimo passo manuale: aprire un NUOVO login SSH (password corretta) prima di chiudere questa sessione"
exit $rc
