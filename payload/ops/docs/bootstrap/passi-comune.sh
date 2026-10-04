# shellcheck shell=bash
# shellcheck disable=SC2034  # variabili impostate qui e usate dagli script che includono questo file
# passi-comune.sh — funzioni comuni agli script dei passi della checklist (passo*.sh), incluso con "source".
#
# Gli script girano come root: host.conf (file dell'amministratore) viene LETTO riga per riga, mai eseguito; si usano
# solo le chiavi note, con valori validati. Le impostazioni della macchina stanno solo in host.conf e in
# /etc/os-release: gli script non contengono valori di una macchina specifica.

OPS=${OPS_DIR:-/srv/ops}
HOSTCONF=$OPS/host.conf
# OPS_TEMPLATES / OPS_MAINT_DIR: copie verificate preparate da ops-installa (root), altrimenti quelle di /srv/ops
TEMPLATES=${OPS_TEMPLATES:-$OPS/maint/templates}
MAINT_SRC=${OPS_MAINT_DIR:-$OPS/maint}

# valore dell'ultima assegnazione KEY=... (virgolette e commento finale tolti, nessuna espansione)
hc_get() {
  local line v
  line=$(grep -E "^$1=" "$HOSTCONF" | tail -1 || true)
  v=${line#*=}
  case $v in
    \"*) v=${v#\"}; v=${v%%\"*} ;;
    \'*) v=${v#\'}; v=${v%%\'*} ;;
    *) v=${v%%[[:space:]]*} ;;
  esac
  printf '%s' "$v"
}

# carica e valida i parametri usati dagli script; un valore mancante o non valido ferma lo script prima di tutto
load_host_conf() {
  [ -f "$HOSTCONF" ] && [ ! -L "$HOSTCONF" ] || die "manca $HOSTCONF (sezione 0 della checklist)"
  HOST=$(hc_get HOST); ADMIN=$(hc_get ADMIN); LAN_CIDR=$(hc_get LAN_CIDR); DATA_MOUNT=$(hc_get DATA_MOUNT)
  BORG_REPO=$(hc_get BORG_REPO); SERVICES=$(hc_get SERVICES); CONTAINERS=$(hc_get CONTAINERS)
  SQLITE_SNAPSHOTS=$(hc_get SQLITE_SNAPSHOTS)
  [[ "$HOST" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || die "HOST non valido in $HOSTCONF"
  [ "$HOST" = "$(hostname -s)" ] || die "HOST=$HOST in $HOSTCONF diverso dall'hostname ($(hostname -s))"
  [[ "$ADMIN" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && id -u "$ADMIN" >/dev/null 2>&1 || die "ADMIN non valido in $HOSTCONF"
  [[ "$SERVICES" =~ ^[A-Za-z0-9@._\ -]*$ ]] || die "SERVICES non valido in $HOSTCONF"
  [[ "$CONTAINERS" =~ ^[A-Za-z0-9_.\ -]*$ ]] || die "CONTAINERS non valido in $HOSTCONF"
  [[ "${SQLITE_SNAPSHOTS:-0}" =~ ^[0-9]+$ ]] || die "SQLITE_SNAPSHOTS non valido in $HOSTCONF"
  for v in DATA_MOUNT BORG_REPO; do
    [ -z "${!v}" ] || [[ "${!v}" =~ ^/[A-Za-z0-9/._-]*[A-Za-z0-9._-]$ ]] || die "$v non valido in $HOSTCONF: ${!v}"
  done
  if [ -n "$LAN_CIDR" ]; then
    python3 -c 'import ipaddress, sys; ipaddress.ip_network(sys.argv[1])' "$LAN_CIDR" 2>/dev/null \
      || die "LAN_CIDR non valido in $HOSTCONF: $LAN_CIDR (atteso un indirizzo di rete, es. 192.168.1.0/24)"
  fi
}

need() {  # need VAR "spiegazione": il parametro deve essere compilato
  [ -n "${!1}" ] || die "$1 vuoto in $HOSTCONF: $2"
}

# release Ubuntu ed espressione regolare delle origini APT ammesse (etichette di apt-get -s)
load_os_release() {
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${VERSION_ID:-}" =~ ^[0-9]+\.[0-9]+$ ]] && [[ "${VERSION_CODENAME:-}" =~ ^[a-z]+$ ]] || die "versione Ubuntu non riconosciuta"
  UBUNTU_ORIGIN_RE="Ubuntu:${VERSION_ID//./\\.}/${VERSION_CODENAME}(-updates|-security)?"
}
