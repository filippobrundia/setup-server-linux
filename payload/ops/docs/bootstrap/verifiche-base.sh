#!/bin/bash
# Verifiche della configurazione iniziale che non hanno uno script di passo proprio (root, SOLA LETTURA).
# Le lancia ops-installa, una per voce; si possono lanciare anche a mano:
#   sudo bash /srv/ops/docs/bootstrap/verifiche-base.sh <voce>
#
#   inizio        1     rilevazione iniziale (hardware, Ubuntu, dischi, rete, accesso): solo registrazione
#   dischi        2     punti di montaggio di MOUNTS, findmnt --verify, TRIM
#   repo          4     repository /srv/ops e copia della Knowledge Base (kb status come amministratore)
#   rete          7.1   indirizzo statico sull'interfaccia della route di default, gateway in LAN_CIDR, DNS
#   offsite       10.3  /etc/cron.d/offsite-sync compilato e rclone check --size-only con 0 differenze
#   gate          11.1  quick-check --gate con uscita 0; con 10.3 esclusa: bloccato solo dalla copia remota (atteso)
#   healthchecks  11.2  controllo Healthchecks "up"
#   dopo-riavvio  12.4  montaggi, unit, journal del boot precedente, servizi, container, UFW
#   monitoraggio  12.6  quick-check senza ERRORE; Healthchecks "up" se 11.2 non è escluso
#   agenti        12.7  cli-update --verify (AGENTS.md caricato, permessi conformi)
# Esito 0 = superata, 1 = non superata (righe KO), 2 = uso errato. Nessuna modifica al sistema.
set -euo pipefail

# shellcheck source=passi-comune.sh
. "$(dirname "$0")/passi-comune.sh"
die() { echo "ERRORE: $*" >&2; exit 1; }
ok() { echo "ok  $*"; }
ko() { echo "KO  $*"; bad=1; }
nota() { echo "  $*"; }
[ "$(id -u)" -eq 0 ] || die "va eseguito con sudo"
export LC_ALL=C.UTF-8
load_host_conf
MOUNTS=$(hc_get MOUNTS); OFFSITE=$(hc_get OFFSITE); ESCLUSIONI=$(hc_get ESCLUSIONI)
excluded() { [[ " $ESCLUSIONI " == *" $1 "* ]]; }
as_admin() { runuser -u "$ADMIN" -- "$@"; }
bad=0

v_inizio() {
  for c in "lsb_release -ds" "uname -r" "lscpu" "free -h" "lsblk -o NAME,SIZE,TYPE,ROTA,TRAN,MODEL,FSTYPE,MOUNTPOINTS" \
           "findmnt --real" "df -hT" "swapon --show" "ip -br addr" "ip route" "resolvectl status" "ss -tulpn"; do
    echo "== $c"; $c 2>&1 || echo "(codice $?)"
  done
  echo "== errori del kernel già presenti in questo avvio (journalctl -k -b -p err)"
  journalctl -k -b -p err --no-pager -q 2>&1 || true
  ok "rilevazione registrata (da riportare in docs/overview.md e nella sezione \"Il server in tre righe\" di AGENTS.md)"
}

v_dischi() {
  local m fv
  for m in $MOUNTS; do findmnt -n "$m" >/dev/null && ok "$m montato ($(findmnt -n -o SOURCE,FSTYPE "$m"))" || ko "$m non montato"; done
  if findmnt -n --mountpoint /srv >/dev/null; then nota "/srv su un filesystem proprio"; else nota "/srv sul filesystem radice (layout a disco unico)"; fi
  fv=$(findmnt --verify 2>&1 || true)
  grep -qE '^0 parse errors, 0 errors' <<<"$fv" && ok "findmnt --verify: 0 errori" || { ko "findmnt --verify:"; echo "$fv" | sed 's/^/    /'; }
  if [ "$(systemctl is-enabled fstrim.timer 2>/dev/null || true)" = enabled ]; then ok "fstrim.timer abilitato"
  elif lsblk -dn -o DISC-GRAN | grep -qv '^ *0B$'; then ko "fstrim.timer non abilitato con dischi che supportano TRIM (sudo systemctl enable --now fstrim.timer)"
  else nota "fstrim.timer non abilitato, nessun disco con TRIM"; fi
}

v_repo() {
  local st
  [ -d "$OPS/.git" ] && ok "$OPS è un repository Git" || ko "$OPS senza repository Git (rieseguire bootstrap.sh)"
  if [ -d "$OPS/knowledge-base/.git" ] && st=$(as_admin "$OPS/bin/kb" status 2>&1); then ok "Knowledge Base: ${st%%$'\n'*}"
  else ko "Knowledge Base non disponibile: registrare la deploy key del server (~$ADMIN/.ssh/kb_deploy.pub) e poi, come $ADMIN, /srv/ops/bin/kb init"; fi
}

v_rete() {
  local dev gw addr
  read -r dev gw < <(ip -4 route show default | awk '{for (i=1;i<NF;i++) {if ($i=="dev") d=$(i+1); if ($i=="via") g=$(i+1)}; print d, g; exit}') || true
  [ -n "${dev:-}" ] || { ko "nessuna route di default IPv4"; return; }
  addr=$(ip -o -4 addr show dev "$dev" | awk 'NR == 1')
  nota "interfaccia $dev: $(awk '{print $4}' <<<"$addr"), gateway ${gw:-?}"
  [[ "$addr" == *" dynamic "* ]] && ko "indirizzo assegnato da DHCP su $dev: rete non stabile (sezione 7.1, netplan; oppure 7.1 in ESCLUSIONI)" \
    || ok "indirizzo statico su $dev"
  [ -n "$LAN_CIDR" ] && python3 -c 'import ipaddress,sys; sys.exit(0 if ipaddress.ip_address(sys.argv[1]) in ipaddress.ip_network(sys.argv[2]) else 1)' "${gw:-0.0.0.0}" "$LAN_CIDR" \
    && ok "gateway $gw in LAN_CIDR $LAN_CIDR" || ko "gateway ${gw:-?} fuori da LAN_CIDR ${LAN_CIDR:-(vuoto)}"
  getent hosts ubuntu.com >/dev/null && ok "risoluzione DNS" || ko "risoluzione DNS non riuscita"
}

v_offsite() {
  local f=/etc/cron.d/offsite-sync line src dst
  [ -n "$OFFSITE" ] && ok "OFFSITE in host.conf: $OFFSITE" || ko "OFFSITE vuoto in host.conf"
  [ -f "$f" ] || { ko "manca $f (sezione 10.3: remote rclone di root con le credenziali del proprietario)"; return; }
  line=$(grep -m 1 -E '^[^#].* rclone sync ' "$f" || true)
  [ -n "$line" ] && ! grep -q '<' <<<"$line" || { ko "$f senza una riga rclone sync compilata"; return; }
  read -r src dst < <(sed -E 's/.* rclone sync +([^ ]+) +([^ ]+).*/\1 \2/' <<<"$line") || true
  [ "$src" = "$BORG_REPO" ] && ok "$f copia $BORG_REPO" || ko "$f copia $src (BORG_REPO=$BORG_REPO)"
  rclone check --size-only "$src" "$dst" >/dev/null 2>&1 && ok "rclone check --size-only: 0 differenze" || ko "rclone check --size-only: differenze o destinazione non raggiungibile"
}

v_gate() {
  local out rc=0 others
  out=$(as_admin "$OPS/bin/quick-check" --gate 2>&1) || rc=$?
  echo "$out" | sed 's/^/  /'
  if [ "$rc" -eq 0 ]; then ok "quick-check --gate: uscita 0"; return; fi
  # con 10.3 esclusa il gate DEVE restare bloccato dalla sola copia remota: collaudo locale, non produzione
  others=$(grep -E '^  (ATTENZIONE|ERRORE)' <<<"$out" | grep -v 'ATTENZIONE copia remota non configurata' || true)
  if excluded 10.3 && [ "$rc" -eq 1 ] && [ -z "$others" ] && grep -q 'ATTENZIONE copia remota non configurata' <<<"$out"; then
    ok "quick-check --gate bloccato SOLO dalla copia remota (10.3 esclusa): resto sano; finestra e ops-maint attended restano bloccati"
  else
    ko "quick-check --gate: uscita $rc"
  fi
}

v_healthchecks() {
  local out
  out=$(as_admin "$OPS/bin/healthchecks" status 2>&1) || true
  echo "$out" | sed 's/^/  /'
  grep -qw up <<<"$out" && ok "Healthchecks: up" || ko "Healthchecks non in stato up (passaggi personali del runbook monitoraggio-esterno.md, poi bin/healthchecks setup)"
}

v_dopo_riavvio() {
  local fv f u inactive="" st c
  fv=$(findmnt --verify 2>&1 || true)
  grep -qE '^0 parse errors, 0 errors' <<<"$fv" && ok "findmnt --verify: 0 errori" || ko "findmnt --verify segnala errori"
  f=$(systemctl --failed --plain --no-legend | awk '{print $1}' | paste -sd' ')
  [ -z "$f" ] && ok "nessuna unit fallita" || ko "unit fallite: $f"
  journalctl -b -1 -n 1 --no-pager -q >/dev/null 2>&1 && ok "journal del boot precedente disponibile" || ko "journal del boot precedente non disponibile"
  u=$(journalctl -b -1 --no-pager -q 2>/dev/null | grep -iE 'failed unmounting|target is busy' || true)
  [ -z "$u" ] && ok "spegnimento senza 'failed unmounting / target is busy'" || { nota "DA REGISTRARE in STATUS.md (controllo ereditato):"; echo "$u" | sed 's/^/    /'; }
  for s in $SERVICES; do systemctl is-active --quiet "$s" || inactive="$inactive $s"; done
  [ -z "$inactive" ] && ok "servizi attivi: $SERVICES" || ko "servizi non attivi:$inactive"
  if [ -n "$CONTAINERS" ]; then
    for c in $CONTAINERS; do docker ps --format '{{.Names}}' | grep -qx "$c" || ko "container non attivo: $c"; done
  fi
  st=$(ufw status 2>&1 || true)
  grep -qx 'Status: active' <<<"$st" && grep -qE "^22/tcp +LIMIT +${LAN_CIDR//./\\.}( |$)" <<<"$st" && ok "UFW attivo con limit 22/tcp da $LAN_CIDR" || ko "UFW non attivo o regola SSH assente"
  if [ -e /var/lib/ops-maint/postboot-pending ]; then ko "verifica ops-postboot ancora pendente"; fi
  [ ! -e /var/lib/ops-maint/hold ] && ok "manutenzione non sospesa" || ko "manutenzione sospesa: $(cat /var/lib/ops-maint/hold)"
  grep -E ' postboot: ' /var/lib/ops-maint/history.log 2>/dev/null | tail -n 1 | sed 's/^/  ultimo evento postboot: /' || true
}

v_monitoraggio() {
  local out rc=0
  out=$(as_admin "$OPS/bin/quick-check" 2>&1) || rc=$?
  echo "$out" | sed 's/^/  /'
  [ "$rc" -le 1 ] && ! grep -q '^  ERRORE' <<<"$out" && ok "quick-check senza ERRORE (uscita $rc)" || ko "quick-check con errori (uscita $rc)"
  excluded 11.2 && nota "Healthchecks: 11.2 in ESCLUSIONI" || v_healthchecks
}

v_agenti() {
  local out rc=0
  out=$(as_admin "$OPS/bin/cli-update" --verify 2>&1) || rc=$?
  echo "$out" | sed 's/^/  /'
  [ "$rc" -eq 0 ] && ok "cli-update --verify superato" || ko "cli-update --verify: uscita $rc (login degli agenti, permessi o caricamento di AGENTS.md)"
}

case "${1:-}" in
  inizio) v_inizio ;; dischi) v_dischi ;; repo) v_repo ;; rete) v_rete ;; offsite) v_offsite ;; gate) v_gate ;;
  healthchecks) v_healthchecks ;; dopo-riavvio) v_dopo_riavvio ;; monitoraggio) v_monitoraggio ;; agenti) v_agenti ;;
  *) sed -n '2,17p' "$0"; exit 2 ;;
esac
echo "ESITO VERIFICA ${1}=$bad"
exit $bad
