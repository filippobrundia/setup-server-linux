#!/bin/bash
# Passo 8.1 — Docker CE e Compose dal repository ufficiale download.docker.com (decisione ereditata), per la release
# Ubuntu in uso (/etc/os-release; collaudato su 26.04).
#
# Uso (terminale vero, fuori da 06:00–07:00 UTC):
#   sudo bash /srv/ops/docs/bootstrap/passo8-docker.sh --dry-run  # controlli e simulazione APT (nessuna modifica alla
#                                                                 # configurazione; apt-get update aggiorna gli elenchi)
#   sudo bash /srv/ops/docs/bootstrap/passo8-docker.sh            # installazione + VERIFY
#   sudo bash /srv/ops/docs/bootstrap/passo8-docker.sh --rollback # remove (non purge) dei pacchetti installati,
#                                                                 # repository e daemon.json tolti; /srv/docker resta
#
# - Chiave del repository accettata solo con l'impronta ufficiale FP; sorgente deb822 con Signed-By.
# - docker.service e docker.socket MASCHERATI durante l'installazione (il postinst li avvierebbe): daemon.json viene
#   validato con "dockerd --validate" prima del primo avvio, poi smascherati e avviati.
# - daemon.json = maint/templates/docker-daemon.json, invariato (data-root letto dal modello).
# - Nessun utente nel gruppo docker (regola generale del pacchetto, docs/decisions.md): docker con sudo.
# - docker.service aggiunto a REQUIRED_UNITS di /etc/ops-maint.conf: si legge e si modifica SOLO la riga di
#   assegnazione (mai un grep sull'intero file, che trova anche i commenti), come unità separata da spazio
#   ("a|b" significa "una delle due"); i parametri vengono poi riletti da ops-maint.
# - Prova finale con l'immagine ufficiale busybox (scaricata da Docker Hub e poi rimossa): uscita verso Internet dai
#   container e porta pubblicata esplicitamente su 127.0.0.1 (la prova non espone nulla verso la rete).
# - APT: 0 rimozioni, 0 aggiornamenti, origini solo la release Ubuntu in uso e Docker; errore di APT = stato
#   riconciliato nel manifest, maschere mantenute, codice originale, nessuna disinstallazione automatica.
set -euo pipefail

FP=9DC858229FC7DD38854AE2D88D81803C0EBFCD88
KEY=/etc/apt/keyrings/docker.asc
SRC=/etc/apt/sources.list.d/docker.sources
DAEMON=/etc/docker/daemon.json
PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin pigz)
UNITS=(docker.socket docker.service)
MAINT_CONF=/etc/ops-maint.conf
STATE_DIR=/var/lib/ops-bootstrap
MANIFEST=$STATE_DIR/passo8-docker.manifest
APT_OPTS=(-o DPkg::Lock::Timeout=600)
TEST_IMG=busybox:latest
TEST_PORT=18080
BAK_SUFFIX=.bak-$(date -u +%F)

# shellcheck source=passi-comune.sh
. "$(dirname "$0")/passi-comune.sh"
TEMPLATE=$TEMPLATES/docker-daemon.json

MODE=apply
case "${1:-}" in
  "") ;;
  --dry-run) MODE=dry ;;
  --rollback) MODE=rollback ;;
  *) echo "argomento sconosciuto: $1" >&2; exit 2 ;;
esac

die() { echo "ERRORE: $*" >&2; exit 1; }
ok() { echo "ok  $*"; }
ko() { echo "KO  $*"; bad=1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
attrs() { stat -c '%U:%G %a' -- "$1"; }
rec() { echo "$(now) $*" >> "$MANIFEST"; }
pkg_state() {
  local s; s=$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true)
  case "$s" in "install ok installed") echo installed ;; ""|*" not-installed"|*" config-files") echo absent ;; *) echo "half:${s##* }" ;; esac
}
is_masked() { [ -L "/etc/systemd/system/$1" ] && [ "$(readlink -- "/etc/systemd/system/$1")" = /dev/null ]; }
last() { [ -f "$MANIFEST" ] && awk -v k="$1" '$2==k{s=$3} END{print s}' "$MANIFEST"; }
reconcile() {
  local p
  for p in $(awk '$2=="pkg-before"||$2=="pkg"{l[$3]=$2; s[$3]=$4} END{for (p in l) if (l[p]=="pkg-before" || s[p] ~ /^half:/) print p}' "$MANIFEST" | sort); do
    rec pkg "$p" "$(pkg_state "$p")"
  done
}
check_state() {
  if [ -e "$STATE_DIR" ]; then [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ] && [ "$(attrs "$STATE_DIR")" = "root:root 700" ] || die "$STATE_DIR non è root 0700"; fi
  if [ -e "$MANIFEST" ]; then [ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] && [ "$(attrs "$MANIFEST")" = "root:root 600" ] || die "$MANIFEST non è root 0600"; fi
}
desired_daemon() { cat -- "$TEMPLATE"; }
# REQUIRED_UNITS: solo la riga di assegnazione (come la legge ops-maint)
req_units() { awk 'index($0, "REQUIRED_UNITS=") == 1 { print substr($0, 16); exit }' "$MAINT_CONF"; }
has_unit() { local t; for t in $(req_units); do [ "$t" = "$1" ] && return 0; done; return 1; }

[ "$(id -u)" -eq 0 ] || die "va eseguito con sudo"
export LC_ALL=C.UTF-8
load_host_conf
load_os_release
SUITE=$VERSION_CODENAME
ORIGIN_RE="($UBUNTU_ORIGIN_RE|Docker CE:$SUITE) "
DATA_ROOT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["data-root"])' "$TEMPLATE") \
  || die "modello $TEMPLATE non valido"
[[ "$DATA_ROOT" =~ ^/[A-Za-z0-9/._-]+$ ]] || die "data-root non valido nel modello: $DATA_ROOT"
check_state

# ---- ROLLBACK: solo ciò che il manifest dà come introdotto da questo script
if [ "$MODE" = rollback ]; then
  echo "== ROLLBACK"
  [ -f "$MANIFEST" ] || die "nessun manifest: questo script non ha installato nulla"
  reconcile
  systemctl stop docker.service docker.socket 2>/dev/null || true
  mapfile -t P < <(awk '$2=="pkg"{s[$3]=$4} END{for (p in s) if (s[p]=="installed" || s[p] ~ /^half:/) print p}' "$MANIFEST" | sort)
  rrc=0
  if [ "${#P[@]}" -gt 0 ]; then
    SIM=$(apt-get -s "${APT_OPTS[@]}" remove "${P[@]}")
    extra=$(grep '^Remv ' <<<"$SIM" | awk '{print $2}' | grep -vxF -f <(printf '%s\n' "${P[@]}") || true)
    [ -z "$extra" ] || die "la rimozione toccherebbe pacchetti non installati da questo script: $extra"
    apt-get "${APT_OPTS[@]}" remove -y "${P[@]}" || rrc=$?
    for p in "${P[@]}"; do rec pkg "$p" "$(pkg_state "$p")"; done
  fi
  for u in "${UNITS[@]}"; do [ "$(last "mask-$u")" = created ] && is_masked "$u" && { systemctl unmask "$u"; rec "mask-$u" removed; }; done
  for f in "$SRC" "$KEY" "$DAEMON"; do
    if [ "$(last "file-$f")" = created ] && [ -f "$f" ]; then mv -f -- "$f" "$f.rollback-$(date -u +%F)"; rec "file-$f" removed; echo "spostato $f in $f.rollback-*"; fi
  done
  [ -f "$MAINT_CONF$BAK_SUFFIX" ] && [ "$(last "file-$MAINT_CONF")" = modified ] && { cp -p -- "$MAINT_CONF$BAK_SUFFIX" "$MAINT_CONF"; rec "file-$MAINT_CONF" restored; }
  apt-get "${APT_OPTS[@]}" update -qq || true
  echo "lasciati: $DATA_ROOT e /var/lib/containerd (cancellazione dati solo con consenso), gruppo docker (vuoto)"
  exit "$rrc"
fi

# ---- PRECHECK
echo "== PRECHECK"
[ "$(date -u +%H)" != 06 ] || die "06:00–07:00 UTC: finestra degli aggiornamenti automatici"
systemctl is-active --quiet apt-daily-upgrade.service && die "aggiornamenti automatici in corso"
[ -z "$(dpkg --audit 2>&1)" ] || die "dpkg segnala pacchetti non configurati: sudo dpkg --configure -a"
resume=0; [ -f "$MANIFEST" ] && resume=1
for p in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  [ "$(pkg_state "$p")" = absent ] || die "pacchetto in conflitto installato: $p (la procedura Docker chiede di rimuoverlo: da valutare)"
done
if [ "$resume" = 0 ]; then
  for p in "${PKGS[@]}"; do [ "$(pkg_state "$p")" = absent ] || die "$p già installato senza manifest: stato da valutare a mano"; done
  for f in "$KEY" "$SRC" "$DAEMON"; do [ ! -e "$f" ] || die "$f esiste già: stato da valutare a mano"; done
  [ ! -e /var/lib/docker ] || die "/var/lib/docker esiste già"
  if [ -e "$DATA_ROOT" ]; then [ -d "$DATA_ROOT" ] && [ -z "$(ls -A "$DATA_ROOT")" ] || die "$DATA_ROOT esiste e non è una cartella vuota"; fi
else
  echo "nota: ripresa di un'esecuzione precedente (manifest presente)"
fi
getent group docker >/dev/null && { m=$(getent group docker | cut -d: -f4); [ -z "$m" ] || die "gruppo docker con membri: $m"; }
id -nG "$ADMIN" | tr ' ' '\n' | grep -qx docker && die "$ADMIN è nel gruppo docker"
echo "  $DATA_ROOT su $(findmnt -n -o TARGET,SOURCE,FSTYPE --target "$(dirname "$DATA_ROOT")")"
echo "  spazio libero per $DATA_ROOT: $(df -h --output=avail "$(dirname "$DATA_ROOT")" | tail -1 | tr -d ' ')"
ufw status | grep -qx 'Status: active' || die "UFW non attivo: il passo 7 deve essere chiuso"
UFW_BEFORE=$(ufw status numbered)
TMPK=$(mktemp --suffix=.asc); trap 'rm -f "$TMPK"' EXIT
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$TMPK"
got=$(gpg --show-keys --with-colons "$TMPK" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')
[ "$got" = "$FP" ] && ok "chiave Docker con impronta ufficiale $FP" || die "impronta della chiave Docker inattesa: $got"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TEMPLATE" || die "modello daemon.json non valido"
echo "  daemon.json previsto:"; desired_daemon | sed 's/^/    /'
FAILED_BEFORE=$(systemctl --failed --plain --no-legend | awk '{print $1}' | sort)

if [ "$MODE" = dry ]; then
  # simulazione con il repository in una configurazione APT temporanea: nessun file di sistema scritto
  D=$(mktemp -d); trap 'rm -rf "$D" "$TMPK"' EXIT
  mkdir -p "$D/lists/partial" "$D/cache/archives/partial" "$D/src"
  # come le cartelle di APT: lo scaricamento avviene come utente _apt (sandbox), non come root
  chmod 0755 "$D" "$D/lists" "$D/cache" "$D/cache/archives" "$D/src"; chmod 0644 "$TMPK"
  chown _apt:root "$D/lists/partial" "$D/cache/archives/partial"; chmod 0700 "$D/lists/partial" "$D/cache/archives/partial"
  cp /etc/apt/sources.list.d/ubuntu.sources "$D/src/"
  printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: %s\n' \
    "$SUITE" "$(dpkg --print-architecture)" "$TMPK" > "$D/src/docker.sources"
  O=(-o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts="$D/src" -o Dir::State::Lists="$D/lists" -o Dir::Cache="$D/cache")
  apt-get "${O[@]}" update -qq
  SIM=$(apt-get "${O[@]}" -s install --no-install-recommends "${PKGS[@]}")
else
  SIM=""
fi

# ---- MODIFICA
if [ "$MODE" = apply ]; then
  echo "== MODIFICA"
  install -d -o root -g root -m 0700 -- "$STATE_DIR"; ( umask 077; : >> "$MANIFEST" ); chmod 0600 -- "$MANIFEST"
  reconcile
  rec run start
  # 1) repository
  if [ ! -e "$KEY" ]; then install -d -m 0755 /etc/apt/keyrings; install -o root -g root -m 0644 "$TMPK" "$KEY"; rec "file-$KEY" created; fi
  if [ ! -e "$SRC" ]; then
    printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: %s\n' \
      "$SUITE" "$(dpkg --print-architecture)" "$KEY" > "$SRC"; chmod 0644 "$SRC"; rec "file-$SRC" created
  fi
  apt-get "${APT_OPTS[@]}" update -qq
  SIM=$(apt-get -s "${APT_OPTS[@]}" install --no-install-recommends "${PKGS[@]}")
fi
summary=$(grep -E '^[0-9]+ upgraded, [0-9]+ newly installed, [0-9]+ to remove' <<<"$SIM") || die "simulazione APT illeggibile"
echo "simulazione: $summary"
read -r up _ new _ _ rem _ <<<"$summary"
[ "$up" -eq 0 ] && [ "$rem" -eq 0 ] || die "la simulazione prevede aggiornamenti o rimozioni"
bad_origin=$(grep '^Inst ' <<<"$SIM" | grep -vE "$ORIGIN_RE" || true)
[ -z "$bad_origin" ] || die "origini inattese:"$'\n'"$bad_origin"
mapfile -t NEW < <(grep '^Inst ' <<<"$SIM" | awk '{print $2}')
extra=$(printf '%s\n' "${NEW[@]}" | grep -vxF -f <(printf '%s\n' "${PKGS[@]}") || true)
[ -z "$extra" ] || die "pacchetti non previsti nella simulazione: $extra"
grep '^Inst ' <<<"$SIM" | sed -E 's/^Inst ([^ ]+) \(([^ ]+) ([^ ]+).*/  \1 \2 \3/' || echo "  (nessun pacchetto da installare)"
if [ "$MODE" = dry ]; then
  echo "== DRY-RUN: nessuna modifica alla configurazione di sistema (simulazione in una cartella temporanea, poi rimossa)"
  exit 0
fi

# 2) daemon.json prima dei pacchetti (letto al primo avvio)
if [ ! -e "$DAEMON" ]; then
  install -d -o root -g root -m 0755 /etc/docker
  desired_daemon > "$DAEMON"; chmod 0644 "$DAEMON"; rec "file-$DAEMON" created
fi
# 3) servizi mascherati solo se c'è da installare (il postinst non li avvia); in ripresa Docker non va toccato
if [ "${#NEW[@]}" -gt 0 ] && [ "$(pkg_state docker-ce)" != installed ]; then
  for u in "${UNITS[@]}"; do
    if ! is_masked "$u"; then systemctl mask "$u" >/dev/null; is_masked "$u" || die "mascheramento di $u non riuscito"; rec "mask-$u" created; fi
  done
fi
# 4) installazione
if [ "${#NEW[@]}" -gt 0 ]; then
  for p in "${NEW[@]}"; do rec pkg-before "$p" "$(pkg_state "$p")"; done
  arc=0
  apt-get "${APT_OPTS[@]}" install -y --no-install-recommends --no-remove --no-upgrade "${PKGS[@]}" || arc=$?
  reconcile; rec run "apt-exit $arc"
  if [ "$arc" -ne 0 ]; then
    echo "ERRORE: apt-get install terminato con codice $arc; stato reale nel manifest $MANIFEST" >&2
    echo "docker.socket/docker.service restano mascherati. Nessuna disinstallazione automatica." >&2
    echo "Ripresa: capire la causa; se serve sudo dpkg --configure -a; poi rilanciare. Per annullare: --rollback." >&2
    exit "$arc"
  fi
fi
# 5) validazione della configurazione prima del primo avvio, poi avvio
dockerd --validate --config-file "$DAEMON" || die "daemon.json non valido: Docker resta mascherato e fermo"
for u in "${UNITS[@]}"; do [ "$(last "mask-$u")" = created ] && is_masked "$u" && { systemctl unmask "$u" >/dev/null; rec "mask-$u" removed; }; done
systemctl enable --now docker.socket docker.service
# 6) servizio essenziale per la manutenzione (non attivata): solo la riga di assegnazione, unità separata da spazio
if ! has_unit docker.service; then
  [ -e "$MAINT_CONF$BAK_SUFFIX" ] || cp -p -- "$MAINT_CONF" "$MAINT_CONF$BAK_SUFFIX"
  new=$(req_units); new="${new:+$new }docker.service"
  tmp=$(mktemp "$MAINT_CONF.XXXXXX")
  awk -v new="$new" 'index($0, "REQUIRED_UNITS=") == 1 && !done { print "REQUIRED_UNITS=" new; done=1; next } { print }' "$MAINT_CONF" > "$tmp"
  chown root:root "$tmp"; chmod 0644 "$tmp"; mv -f -- "$tmp" "$MAINT_CONF"; rec "file-$MAINT_CONF" modified
fi

# ---- VERIFY
echo "== VERIFY"
bad=0
for p in "${PKGS[@]}"; do [ "$(pkg_state "$p")" = installed ] || ko "$p non installato"; done
echo "  $(docker version --format 'Docker {{.Server.Version}}, API {{.Server.APIVersion}}'); $(docker compose version)"
info=$(docker info --format '{{.DockerRootDir}} {{.Driver}} {{.LoggingDriver}} {{.CgroupDriver}} {{.CgroupVersion}}')
read -r root drv log cgd cgv <<<"$info"
[ "$root" = "$DATA_ROOT" ] && ok "DockerRootDir $root" || ko "DockerRootDir $root (atteso $DATA_ROOT)"
[ "$drv" = overlay2 ] && ok "storage driver overlay2 (immagini in $DATA_ROOT, non nel containerd image store)" \
  || ko "storage driver $drv: immagini fuori da $DATA_ROOT (containerd image store di Docker 29)"
[ "$log" = json-file ] && ok "log json-file $(python3 -c 'import json;print(json.load(open("/etc/docker/daemon.json"))["log-opts"])')" || ko "log driver $log"
echo "  cgroup: $cgd v$cgv; $DATA_ROOT $(attrs "$DATA_ROOT"); /var/lib/containerd $(du -sh /var/lib/containerd 2>/dev/null | cut -f1)"
[ ! -e /var/lib/docker ] && ok "/var/lib/docker non creato" || ko "/var/lib/docker presente"
for u in "${UNITS[@]}" containerd.service; do
  [ "$(systemctl is-enabled "$u")" = enabled ] && systemctl is-active --quiet "$u" && ok "$u abilitato e attivo" || ko "$u non abilitato/attivo"
done
[ "$(stat -c '%U:%G %a' /run/docker.sock)" = "root:docker 660" ] && ok "/run/docker.sock root:docker 0660" || ko "/run/docker.sock $(stat -c '%U:%G %a' /run/docker.sock)"
m=$(getent group docker | cut -d: -f4); [ -z "$m" ] && ok "gruppo docker senza membri ($ADMIN non aggiunto)" || ko "gruppo docker: $m"
# firewall: UFW invariato; Docker aggiunge le sue catene e abilita l'inoltro IPv4
[ "$(ufw status numbered)" = "$UFW_BEFORE" ] && ok "regole UFW invariate" || ko "regole UFW cambiate"
iptables -S DOCKER-USER >/dev/null 2>&1 && ok "catena DOCKER-USER presente (iptables-nft)" || ko "catena DOCKER-USER assente"
echo "  net.ipv4.ip_forward=$(sysctl -n net.ipv4.ip_forward) (abilitato da Docker; FORWARD filtrato da Docker e da UFW deny routed)"
# prova con busybox: uscita verso Internet e porta pubblicata solo su 127.0.0.1
if docker pull -q "$TEST_IMG" >/dev/null; then
  docker run --rm "$TEST_IMG" wget -q -T 10 -O /dev/null http://archive.ubuntu.com/ubuntu/ && ok "container: uscita HTTP verso Internet" || ko "container senza uscita verso Internet"
  docker run -d --rm --name ops-prova-porta -p "127.0.0.1:$TEST_PORT:80" "$TEST_IMG" httpd -f -p 80 >/dev/null
  sleep 1
  L=$(ss -tlnH "( sport = :$TEST_PORT )" | awk '{print $4}' | sort -u | tr '\n' ' ')
  [ "$L" = "127.0.0.1:$TEST_PORT " ] && ok "porta pubblicata su 127.0.0.1:$TEST_PORT" || ko "porta pubblicata su: $L"
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$TEST_PORT/" || true)
  [ "$code" != 000 ] && ok "porta raggiungibile in locale (HTTP $code)" || ko "porta non raggiungibile in locale"
  docker rm -f ops-prova-porta >/dev/null 2>&1 || true
  docker image rm -f "$TEST_IMG" >/dev/null && ok "prova rimossa (container e immagine)"
else
  ko "pull di $TEST_IMG non riuscito: prove di rete non eseguite"
fi
[ -z "$(docker ps -aq)" ] && [ -z "$(docker images -q)" ] && ok "nessun container né immagine residui" || ko "residui: $(docker ps -a --format '{{.Names}}') $(docker images --format '{{.Repository}}')"
has_unit docker.service && ok "$MAINT_CONF: REQUIRED_UNITS=$(req_units)" || ko "REQUIRED_UNITS senza docker.service"
/usr/local/sbin/ops-maint origins >/dev/null && ok "parametri riletti e validati da ops-maint" || ko "parametri di $MAINT_CONF rifiutati da ops-maint"
FAILED_AFTER=$(systemctl --failed --plain --no-legend | awk '{print $1}' | sort)
nf=$(comm -13 <(echo "$FAILED_BEFORE") <(echo "$FAILED_AFTER") | sed '/^$/d'); [ -z "$nf" ] && ok "nessuna nuova unità in errore" || ko "nuove unità in errore: $nf"
echo "  quick-check come $ADMIN:"; runuser -u "$ADMIN" -- "$OPS/bin/quick-check" 2>&1 | grep -A1 '^Docker' | sed 's/^/    /' || true
echo "ESITO PASSO 8=$bad"
exit $bad
