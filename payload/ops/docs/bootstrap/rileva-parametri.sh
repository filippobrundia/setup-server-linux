#!/bin/bash
# Rilevazione dei parametri della macchina per host.conf (sezione 0) — utente amministratore, SENZA sudo, sola lettura
# salvo --scrivi.
#
#   bash /srv/ops/docs/bootstrap/rileva-parametri.sh            proposta di host.conf e dati da chiedere al proprietario
#   bash /srv/ops/docs/bootstrap/rileva-parametri.sh --scrivi [--profilo base|docker] [--esclusioni "7.1 10.3"]
#        scrive in host.conf i valori rilevati SOLO nelle chiavi vuote (mai sovrascritte), più PROFILO ed ESCLUSIONI
#        se indicati; aggiunge le chiavi mancanti di versioni precedenti. Poi: commit e "ops-installa --piano".
#
# Rileva: hostname, amministratore, interfaccia della route di default, indirizzo (statico o DHCP), gateway e rete
# (LAN_CIDR), punti di montaggio (/srv separato, disco dati), Docker già presente. Non rileva e chiede al proprietario
# in una sola volta: profilo, destinazione della copia remota, monitoraggio esterno, approvazione della finestra.
set -euo pipefail
export LC_ALL=C.UTF-8
OPS=${OPS_DIR:-/srv/ops}
HC=$OPS/host.conf
SCRIVI=0; PROF=""; ESCL=""; ESCL_SET=0
while [ $# -gt 0 ]; do
  case $1 in
    --scrivi) SCRIVI=1; shift ;;
    --profilo) PROF=${2:-}; shift 2 ;;
    --esclusioni) ESCL=${2:-}; ESCL_SET=1; shift 2 ;;
    *) echo "opzione sconosciuta: $1" >&2; exit 2 ;;
  esac
done
[ "$(id -u)" != 0 ] || { echo "da eseguire come amministratore, senza sudo" >&2; exit 2; }
case $PROF in ""|base|docker) ;; *) echo "--profilo: base o docker" >&2; exit 2 ;; esac
AMMESSE="2 7.1 10.3 11.2 12.8"
for e in $ESCL; do [[ " $AMMESSE " == *" $e "* ]] || { echo "--esclusioni: '$e' non ammesso ($AMMESSE)" >&2; exit 2; }; done
[ -f "$HC" ] || { echo "manca $HC" >&2; exit 2; }
hc() { local l; l=$(grep -E "^$1=" "$HC" | tail -n 1 || true); l=${l#*=}; case $l in \"*) l=${l#\"}; l=${l%%\"*} ;; *) l=${l%%[[:space:]]*} ;; esac; printf '%s' "$l"; }

# ---- rete
read -r DEV GW < <(ip -4 route show default | awk '{for (i=1;i<NF;i++) {if ($i=="dev") d=$(i+1); if ($i=="via") g=$(i+1)}; print d, g; exit}') || true
ADDR=""; DYN=0; LAN=""
if [ -n "${DEV:-}" ]; then
  line=$(ip -o -4 addr show dev "$DEV" | awk 'NR == 1')
  ADDR=$(awk '{print $4}' <<<"$line"); [[ "$line" == *" dynamic "* ]] && DYN=1
  LAN=$(python3 -c 'import ipaddress,sys; print(ipaddress.ip_interface(sys.argv[1]).network)' "$ADDR" 2>/dev/null || true)
fi
# ---- dischi: /srv separato? disco dati = il filesystem reale più grande montato fuori dal sistema
SRV_SEP=0; findmnt -n --mountpoint /srv >/dev/null && SRV_SEP=1
DATA=$(findmnt -rn --real -o TARGET,SIZE -b | awk '$1 !~ "^/(boot|boot/efi|srv|srv/.*|snap/.*|var/snap/.*)?$" && $1 != "/" {print $2, $1}' | sort -rn | awk 'NR == 1 {print $2}')
[ -n "$DATA" ] || DATA=/srv
MNT="/"; [ "$SRV_SEP" = 1 ] && MNT="$MNT /srv"; [ "$DATA" != /srv ] && MNT="$MNT $DATA"
DOCKER=0; command -v docker >/dev/null && DOCKER=1
P=${PROF:-$(hc PROFILO)}; [ -n "$P" ] || { [ "$DOCKER" = 1 ] && P=docker; }
SVC="ssh cron ufw fail2ban"; [ "${P:-base}" = docker ] && SVC="$SVC docker"

echo "== Rilevato su $(hostname -s) (Ubuntu $(. /etc/os-release; echo "$VERSION_ID"))"
echo "  amministratore: $(id -un)   interfaccia: ${DEV:-?}   indirizzo: ${ADDR:-?} ($([ "$DYN" = 1 ] && echo 'DHCP' || echo 'statico'))   gateway: ${GW:-?}"
echo "  /srv: $([ "$SRV_SEP" = 1 ] && echo 'filesystem proprio' || echo 'sul filesystem radice (disco unico)')   disco dati proposto: $DATA"
echo
echo "== Proposta per $HC (valori già compilati restano)"
for kv in "LAN_CIDR=$LAN" "MOUNTS=$MNT" "DATA_MOUNT=$DATA" "SERVICES=$SVC" "PROFILO=${P:-}" "ESCLUSIONI=$([ "$ESCL_SET" = 1 ] && echo "$ESCL" || hc ESCLUSIONI)"; do
  k=${kv%%=*}; v=${kv#*=}; cur=$(hc "$k")
  printf '  %-11s proposto: %-28s attuale: %s\n' "$k" "\"$v\"" "${cur:-(vuoto)}"
done
echo
echo "== Da decidere con il proprietario (una sola richiesta)"
[ -n "$P" ] || echo "  - PROFILO: base (senza container) oppure docker (base + Docker, passo 8)"
[ "$DYN" = 1 ] && echo "  - 7.1 rete: indirizzo da DHCP. Configurare un indirizzo statico (netplan, passaggio con accesso fisico) oppure escludere 7.1"
[ "$SRV_SEP" = 0 ] && echo "  - 2 dischi: layout a disco unico (cartelle su /). Accettarlo, preparare volumi dedicati (⚠️ distruttivo, a mano) oppure escludere 2"
[ -n "$(hc OFFSITE)" ] || echo "  - 10.3 copia remota: destinazione e credenziali rclone del proprietario (configurazione a mano) oppure escludere 10.3"
MCFG=$(hc MONITOR_CFG); MCFG=${MCFG//\$HOME/$HOME}
[ -s "$MCFG/healthchecks-ping-url" ] || echo "  - 11.2 Healthchecks: passaggi personali del runbook monitoraggio-esterno.md oppure escludere 11.2"
echo "  - 12.8 finestra di manutenzione automatica: approvarla alla fine (conferma scritta in ops-installa) oppure escludere 12.8"

if [ "$SCRIVI" = 1 ]; then
  for kv in "LAN_CIDR=$LAN" "MOUNTS=$MNT" "DATA_MOUNT=$DATA" "SERVICES=$SVC" "PROFILO=$PROF" "ESCLUSIONI=$ESCL"; do
    k=${kv%%=*}; v=${kv#*=}
    grep -qE "^$k=" "$HC" || printf '%s=""\n' "$k" >> "$HC"   # chiave introdotta da una versione successiva
    if [ "$k" = ESCLUSIONI ]; then [ "$ESCL_SET" = 1 ] || continue
    elif [ "$k" = PROFILO ]; then [ -n "$PROF" ] || continue
    elif [ "$k" = SERVICES ] && [ "$(hc SERVICES)" = "ssh cron" ]; then :   # valori iniziali del modello: completati
    elif [ "$k" = MOUNTS ] && [ "$(hc MOUNTS)" = "/" ]; then :
    else [ -z "$(hc "$k")" ] && [ -n "$v" ] || continue; fi
    sed -i -E "s#^$k=(\"[^\"]*\"|'[^']*'|[^[:space:]]*)#$k=\"$v\"#" "$HC"
    echo "  scritto: $k=\"$v\""
  done
  echo "Fatto. Controllare con: git -C $OPS diff host.conf; poi commit e: ops-installa --piano"
fi
