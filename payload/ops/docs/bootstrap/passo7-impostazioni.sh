#!/bin/bash
# Passo 7 — impostazioni di sistema (7.2–7.7). La rete stabile (7.1, netplan) resta un passo manuale da completare
# prima, perché LAN_CIDR deve essere quella definitiva.
#
# Uso (terminale vero, sessione SSH tenuta aperta, console o accesso fisico disponibile):
#   sudo bash /srv/ops/docs/bootstrap/passo7-impostazioni.sh --dry-run  # solo controlli: nessuna modifica alla
#                                                                       # configurazione (verificata), ma log sì
#   sudo bash /srv/ops/docs/bootstrap/passo7-impostazioni.sh            # controlli + attivazione UFW
#   sudo bash /srv/ops/docs/bootstrap/passo7-impostazioni.sh --confirm  # dopo un NUOVO login SSH riuscito:
#                                                                       # annulla il ripristino automatico
#   sudo bash /srv/ops/docs/bootstrap/passo7-impostazioni.sh --rollback # UFW disattivato, regole di prima
#
# Unica modifica: UFW (7.3). Una regola "limit 22/tcp" dalla sola LAN_CIDR di host.conf (obbligatoria: senza una
# rete locale stabile la procedura non si applica e lo script si ferma). Le politiche predefinite di
# /etc/default/ufw devono essere già quelle attese (deny in, allow out, deny routed): vengono solo verificate.
# Prima di "ufw enable" viene armato un timer systemd che esegue
# "ufw disable" dopo ROLLBACK_MIN minuti, se non si conferma con --confirm dopo un nuovo login SSH.
# Il riferimento al backup (suffisso e sha256 delle copie) sta in STATE, root 0600: --rollback lo ritrova anche in
# un altro giorno e non tocca nulla se manca una copia o non corrisponde.
# SSH (7.2), fail2ban (7.4), orario (7.5), aggiornamenti automatici (7.6), journal (7.7): solo verifica; una
# differenza ferma lo script prima di qualunque modifica (nessuna correzione automatica).
set -euo pipefail

ROLLBACK_MIN=10
RB_UNIT=ops-ufw-rollback
UFW_FILES=(/etc/ufw/user.rules /etc/ufw/user6.rules /etc/ufw/ufw.conf)
BAK_SUFFIX=.bak-$(date -u +%F)
STATE_DIR=/var/lib/ops-bootstrap
STATE=$STATE_DIR/passo7-ufw.state
# configurazioni che il --dry-run non deve cambiare (confronto sha256 prima/dopo)
CONF_FILES=("${UFW_FILES[@]}" /etc/default/ufw /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf
            /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/50unattended-upgrades /etc/fail2ban/jail.d/*.conf)

# shellcheck source=passi-comune.sh
. "$(dirname "$0")/passi-comune.sh"

MODE=apply
case "${1:-}" in
  "") ;;
  --dry-run) MODE=dry ;;
  --confirm) MODE=confirm ;;
  --rollback) MODE=rollback ;;
  *) echo "argomento sconosciuto: $1" >&2; exit 2 ;;
esac

die() { echo "ERRORE: $*" >&2; exit 1; }
ok() { echo "ok  $*"; }
ko() { echo "KO  $*"; bad=1; }
[ "$(id -u)" -eq 0 ] || die "va eseguito con sudo"
export LC_ALL=C.UTF-8
load_host_conf
need LAN_CIDR "rete locale ammessa da UFW (sezione 0; rete stabile della sezione 7.1)"
RANGES=("$LAN_CIDR")

attrs() { stat -c '%U:%G %a' -- "$1"; }
check_state() {
  if [ -e "$STATE_DIR" ] || [ -L "$STATE_DIR" ]; then
    [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ] && [ "$(attrs "$STATE_DIR")" = "root:root 700" ] \
      || die "$STATE_DIR non è una cartella root 0700"
  fi
  if [ -e "$STATE" ] || [ -L "$STATE" ]; then
    [ -f "$STATE" ] && [ ! -L "$STATE" ] && [ "$(attrs "$STATE")" = "root:root 600" ] || die "$STATE non è un file root 0600"
  fi
}
# UFW attivo con esattamente le regole LIMIT attese su 22/tcp
rules_ok() {
  local st r; st=$(ufw status) || return 1
  grep -qx 'Status: active' <<<"$st" || return 1
  for r in "${RANGES[@]}"; do grep -qE "^22/tcp +LIMIT +${r//./\\.}( |$)" <<<"$st" || return 1; done
  [ "$(grep -c ' LIMIT ' <<<"$st")" -eq "${#RANGES[@]}" ]
}
# indirizzi dei client SSH collegati ora
ssh_peers() { ss -tnH state established '( sport = :22 )' | awk '{print $4}' | sed -E 's/^\[?(::ffff:)?//; s/\]?:[0-9]+$//' | sort -u; }
# stampa gli indirizzi NON coperti dalle reti ammesse
uncovered() { python3 -c 'import sys, ipaddress as i
nets=[i.ip_network(n) for n in sys.argv[1:]]
for l in sys.stdin:
    a=l.strip()
    if a and not any(i.ip_address(a) in n for n in nets if i.ip_address(a).version == n.version): print(a)' "${RANGES[@]}"; }

if [ "$MODE" = confirm ]; then
  if ! systemctl is-active --quiet "$RB_UNIT.timer"; then
    if rules_ok; then echo "nessun ripristino armato: UFW è già attivo con le regole attese (confermato in precedenza)"; exit 0; fi
    die "nessun ripristino armato e UFW non attivo con le regole attese: il ripristino automatico è probabilmente già scattato (ufw status verbose; rieseguire lo script)"
  fi
  rules_ok || die "UFW non attivo o regole diverse da quelle attese: ripristino automatico LASCIATO armato"
  systemctl stop "$RB_UNIT.timer"
  rules_ok || die "UFW disattivato durante la conferma (ripristino scattato): rieseguire lo script"
  ok "UFW attivo con le ${#RANGES[@]} regole attese; ripristino automatico annullato"
  ufw status verbose
  exit 0
fi

if [ "$MODE" = rollback ]; then
  echo "== ROLLBACK"
  check_state
  [ -f "$STATE" ] || die "nessun intervento registrato ($STATE assente): nulla di sicuro da ripristinare; per disattivare soltanto: sudo ufw disable"
  bak=$(awk -F= '$1=="bak_suffix"{print $2}' "$STATE")
  [[ "$bak" =~ ^\.bak-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "suffisso del backup non valido in $STATE"
  echo "backup dell'intervento del $(awk -F= '$1=="created"{print $2}' "$STATE"): suffisso $bak"
  # tutte le copie devono esistere e corrispondere a quelle registrate, prima di toccare qualunque cosa
  for f in "${UFW_FILES[@]}"; do
    want=$(awk -v f="$f" '$1=="file" && $2==f {print $3}' "$STATE")
    [ -n "$want" ] || die "$f non registrato in $STATE: nessuna modifica"
    [ -f "$f$bak" ] && [ ! -L "$f$bak" ] || die "manca la copia $f$bak: nessuna modifica"
    [ "$(sha256sum < "$f$bak" | cut -d' ' -f1)" = "$want" ] || die "$f$bak diverso da quello registrato: nessuna modifica"
  done
  ok "copie presenti e integre"
  systemctl stop "$RB_UNIT.timer" 2>/dev/null || true
  ufw disable
  for f in "${UFW_FILES[@]}"; do cp -p -- "$f$bak" "$f"; echo "ripristinato $f da $f$bak"; done
  ufw status verbose; ufw show added
  exit 0
fi

bad=0
check_state
T0=$(date '+%Y-%m-%d %H:%M:%S.%N')
CONF_BEFORE=$(sha256sum -- "${CONF_FILES[@]}" 2>&1)
echo "== PRECHECK: SSH (7.2)"
sshd -t || die "sshd -t: configurazione non valida"
T=$(sshd -T)
# atteso: decisione ereditata del 2026-08-02 (sshd -T può stampare "without-password", sinonimo di prohibit-password)
for kv in "port 22" "permitrootlogin prohibit-password|without-password" "passwordauthentication yes" "pubkeyauthentication yes"; do
  k=${kv%% *}; v=${kv#* }; got=$(awk -v k="$k" '$1==k{print $2}' <<<"$T")
  [[ "$got" =~ ^($v)$ ]] && ok "sshd $k $got" || ko "sshd $k $got (atteso $v)"
done
echo "  sshd_config.d: $(ls /etc/ssh/sshd_config.d/ | tr '\n' ' ')"
systemctl is-active --quiet ssh.socket && ok "ssh.socket attivo" || ko "ssh.socket non attivo"

echo "== PRECHECK: fail2ban (7.4)"
fail2ban-client status sshd | sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<IP>/g; s/^/  /'
[ "$(fail2ban-client get sshd banned)" = "[]" ] && ok "fail2ban: nessun IP bandito" || ko "fail2ban: IP banditi presenti"
[ "$(systemctl is-enabled fail2ban)" = enabled ] && ok "fail2ban abilitato all'avvio" || ko "fail2ban non abilitato all'avvio"

echo "== PRECHECK: orario (7.5)"
[ "$(timedatectl show -P Timezone)" = Etc/UTC ] && ok "Timezone Etc/UTC" || ko "Timezone $(timedatectl show -P Timezone)"
ntpc=$(for u in chrony systemd-timesyncd; do if systemctl is-active --quiet "$u"; then echo "$u"; fi; done | paste -sd' ')
[ "$(timedatectl show -P NTPSynchronized)" = yes ] && ok "NTPSynchronized=yes (client attivo: ${ntpc:-nessuno noto})" || ko "NTP non sincronizzato"

echo "== PRECHECK: aggiornamenti automatici (7.6)"
cmp -s /etc/apt/apt.conf.d/20auto-upgrades "$TEMPLATES/20auto-upgrades" && ok "20auto-upgrades = modello" || ko "20auto-upgrades diverso dal modello"
[ -z "$(dpkg -V unattended-upgrades)" ] && ok "50unattended-upgrades di default" || ko "file di unattended-upgrades modificati: $(dpkg -V unattended-upgrades)"
rb=$(apt-config dump | awk -F'"' '/^Unattended-Upgrade::Automatic-Reboot /{print $2}')
[ "${rb:-false}" = false ] && ok "riavvio automatico disattivato" || ko "Automatic-Reboot=$rb"
if [ "$(date -u +%H)" = 06 ] || systemctl is-active --quiet apt-daily-upgrade.service; then
  echo "  unattended-upgrade --dry-run saltato: aggiornamenti automatici in corso o fascia 06–07 UTC (ripetere dopo)"
else
  out=$(unattended-upgrade --dry-run 2>&1) && ok "unattended-upgrade --dry-run senza errori" \
    || { ko "unattended-upgrade --dry-run fallito:"; tail -5 <<<"$out"; }
fi

echo "== PRECHECK: log (7.7)"
[ -d /var/log/journal ] && ok "journal persistente ($(journalctl --disk-usage | grep -oE '[0-9.]+[KMG]'))" || ko "manca /var/log/journal"

echo "== PRECHECK: UFW (7.3)"
grep -qx 'ENABLED=no' /etc/ufw/ufw.conf || die "UFW risulta già abilitato: nessuna modifica, da valutare a mano"
added=$(ufw show added)
grep -qx '(None)' <<<"$(tail -1 <<<"$added")" || { echo "$added"; die "UFW ha già regole: nessuna modifica, da valutare a mano"; }
for kv in DEFAULT_INPUT_POLICY=\"DROP\" DEFAULT_OUTPUT_POLICY=\"ACCEPT\" DEFAULT_FORWARD_POLICY=\"DROP\"; do
  grep -qx "$kv" /etc/default/ufw && ok "/etc/default/ufw $kv" || ko "/etc/default/ufw senza $kv"
done
[ "$(systemctl is-enabled ufw)" = enabled ] && ok "ufw.service abilitato all'avvio" || ko "ufw.service non abilitato"
PEERS=$(ssh_peers)
[ -n "$PEERS" ] || die "nessuna sessione SSH stabilita: eseguire da una sessione SSH"
miss=$(uncovered <<<"$PEERS")
[ -z "$miss" ] && ok "le $(wc -l <<<"$PEERS") sorgenti SSH attuali rientrano in LAN_CIDR" \
  || die "sorgenti SSH attuali fuori da LAN_CIDR ($LAN_CIDR): $miss"
gw=$(ip route show default | awk '{print $3; exit}')
[ -z "$(uncovered <<<"$gw")" ] && ok "gateway $gw in LAN_CIDR" || die "gateway $gw fuori da LAN_CIDR ($LAN_CIDR): controllare host.conf e la rete (7.1)"
systemctl is-active --quiet "$RB_UNIT.timer" && die "$RB_UNIT.timer già armato: confermare o ripristinare prima"

[ "$bad" -eq 0 ] || die "controlli non superati: nessuna modifica eseguita"
echo "regole previste:"; for r in "${RANGES[@]}"; do echo "  ufw limit from $r to any port 22 proto tcp"; done
if [ "$MODE" = dry ]; then
  echo "== DRY-RUN: scritture verificate"
  [ "$(sha256sum -- "${CONF_FILES[@]}" 2>&1)" = "$CONF_BEFORE" ] \
    && ok "configurazione invariata (${#CONF_FILES[@]} file: UFW, SSH, APT, fail2ban)" || { ko "configurazione cambiata durante il dry-run"; exit 1; }
  # non è "nessuna scrittura": unattended-upgrade --dry-run scrive nel suo log e usa un lock, sudo scrive nel journal
  echo "  file scritti durante il dry-run (log, lock, cache; journal escluso):"
  # elenco in una variabile, stampa senza pipe (con pipefail un lettore che chiude prima dava uscita 141)
  written=$(find /etc /var/log /var/lib /var/cache /run -xdev -type f -newermt "$T0" ! -path '/var/log/journal/*' 2>/dev/null || true)
  awk 'NR <= 20 { print "    " $0 }' <<<"$written"
  exit 0
fi

echo "== BACKUP"
# una copia già presente con lo stesso nome si riusa solo se identica al file attuale (per esempio dopo un rollback)
for f in "${UFW_FILES[@]}"; do
  if [ -e "$f$BAK_SUFFIX" ]; then cmp -s -- "$f" "$f$BAK_SUFFIX" || die "$f$BAK_SUFFIX esiste ed è diverso da $f: nessuna modifica"
  else cp -p -- "$f" "$f$BAK_SUFFIX"; fi
  echo "  $f$BAK_SUFFIX"
done
# riferimento persistente al backup, scritto prima di qualunque modifica
install -d -o root -g root -m 0700 -- "$STATE_DIR"
tmp=$(mktemp "$STATE_DIR/.passo7-ufw.XXXXXX")
{ echo "bak_suffix=$BAK_SUFFIX"; echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for f in "${UFW_FILES[@]}"; do echo "file $f $(sha256sum < "$f$BAK_SUFFIX" | cut -d' ' -f1)"; done; } > "$tmp"
chmod 0600 -- "$tmp"; mv -f -- "$tmp" "$STATE"
check_state
echo "  stato: $STATE"

echo "== MODIFICA"
for r in "${RANGES[@]}"; do ufw limit from "$r" to any port 22 proto tcp comment 'SSH dalla LAN'; done
# ripristino automatico armato PRIMA dell'attivazione: se l'accesso si perde, UFW si disattiva da solo
RB_AT=$(date -d "+${ROLLBACK_MIN} min" '+%F %T %Z')   # timer monotono: l'ora reale di systemctl show resta vuota
systemd-run --quiet --unit="$RB_UNIT" --on-active="${ROLLBACK_MIN}min" --timer-property=AccuracySec=1s \
  /usr/sbin/ufw disable
systemctl is-active --quiet "$RB_UNIT.timer" || die "timer di ripristino non armato: UFW NON attivato (regole aggiunte, inattive)"
ufw --force enable

echo "== VERIFY"
bad=0
ufw status verbose
rules_ok && ok "UFW attivo con le ${#RANGES[@]} regole LIMIT attese su 22/tcp" || ko "UFW non attivo o regole inattese"
PEERS=$(ssh_peers); miss=$(uncovered <<<"$PEERS")
[ -n "$PEERS" ] && [ -z "$miss" ] && ok "sessione SSH ancora stabilita dopo l'attivazione" || ko "sorgenti fuori regola: $miss"
echo "  ripristino automatico: verso le $RB_AT ($RB_UNIT.timer)"
echo
echo "ORA: apri un NUOVO login SSH (password corretta). Se riesce:"
echo "  sudo bash $OPS/docs/bootstrap/passo7-impostazioni.sh --confirm"
echo "Se non riesce: entro $ROLLBACK_MIN minuti UFW si disattiva da solo; oppure dalla console --rollback."
exit $bad
