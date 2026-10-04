#!/bin/bash
# Passo 12 — verifiche del collaudo che richiedono root (solo lettura, salvo una cartella temporanea poi rimossa).
#
# Uso (terminale vero, fuori da 03:00–04:10 UTC):  sudo bash /srv/ops/docs/bootstrap/passo12-verifiche.sh
#
# 12.5  UFW attivo con le politiche attese e la regola SSH da LAN_CIDR (7.3); nessuna regola aperta verso Internet
#       (sorgente "Anywhere"); le altre regole e le porte in ascolto oltre la 22 sono elencate: ognuna va spiegata in
#       docs/network.md.
# 12.2  ripristino di /srv/ops dall'ultimo archivio in /var/tmp/ops-restore-* (mai sopra gli originali): diff -r con
#       l'originale e git fsck del repository ripristinato e della copia della Knowledge Base; poi rimozione.
#       Database (PRAGMA integrity_check) e ripristino dalla copia remota: non coperti da questo script.
# 12.4  (prima del riavvio) findmnt --verify; il riavvio presidiato è un passo separato, concordato.
# Nessuna modifica di configurazione; la manutenzione automatica resta disattivata.
set -euo pipefail

# shellcheck source=passi-comune.sh
. "$(dirname "$0")/passi-comune.sh"
die() { echo "ERRORE: $*" >&2; exit 1; }
ok() { echo "ok  $*"; }
ko() { echo "KO  $*"; bad=1; }
[ "$(id -u)" -eq 0 ] || die "va eseguito con sudo"
export LC_ALL=C.UTF-8
load_host_conf
need LAN_CIDR "rete locale ammessa da UFW (sezione 0)"
need BORG_REPO "repository Borg locale (sezione 10.1)"
REPO=$BORG_REPO
bad=0
h=$(date -u +%H%M); [ "$h" -lt 0300 ] || [ "$h" -ge 0410 ] || die "03:00–04:10 UTC: finestra del backup notturno"
if pgrep -x borg >/dev/null || pgrep -x borgmatic >/dev/null; then die "borg/borgmatic in esecuzione"; fi

echo "== 12.5 ACCESSI"
st=$(ufw status verbose)
echo "$st" | sed 's/^/  /'
grep -qx 'Status: active' <<<"$st" && ok "UFW attivo" || ko "UFW non attivo"
# senza Docker (ip_forward=0) UFW stampa "disabled (routed)": stesso effetto di "deny (routed)"
grep -qE 'Default: deny \(incoming\), allow \(outgoing\), (deny|disabled) \(routed\)' <<<"$st" && ok "politiche deny in / allow out / deny routed" || ko "politiche inattese"
grep -qE "^22/tcp +LIMIT IN +${LAN_CIDR//./\\.}( |$)" <<<"$st" && ok "limit 22/tcp da $LAN_CIDR" || ko "manca limit 22/tcp da $LAN_CIDR"
open=$(grep -E ' (ALLOW|LIMIT) IN +Anywhere' <<<"$st" || true)
[ -z "$open" ] && ok "nessuna regola aperta verso Internet" || { ko "regole aperte verso Internet:"; echo "$open" | sed 's/^/    /'; }
other=$(grep -E ' (ALLOW|LIMIT|DENY|REJECT) IN ' <<<"$st" | grep -vE "^22/tcp +LIMIT IN +${LAN_CIDR//./\\.}( |$)" || true)
[ -z "$other" ] && ok "solo la regola SSH del passo 7.3" || { echo "  altre regole (da spiegare in docs/network.md):"; echo "$other" | sed 's/^/    /'; }
L=$(ss -tlnH | awk '{print $4}' | grep -vE '^(127\.[0-9.]+(%lo)?|\[::1\]):' | sort -u | tr '\n' ' ')
if [ "$L" = "0.0.0.0:22 [::]:22 " ]; then ok "porte TCP in ascolto verso l'esterno: solo 22"
else echo "  porte TCP in ascolto oltre il loopback (ognuna da spiegare in docs/network.md): $L"; fi
fail2ban-client status sshd | grep -E 'Currently (failed|banned)' | sed 's/^/  /'

echo "== 12.2 PROVA DI RIPRISTINO DI /srv/ops"
A=$(borg list --short --last 1 "$REPO"); [ -n "$A" ] || die "nessun archivio in $REPO"
echo "  archivio: $A"
R=$(mktemp -d /var/tmp/ops-restore-XXXXXX); chmod 0700 "$R"; trap 'rm -rf -- "$R"' EXIT
( cd "$R" && borg extract "$REPO::$A" "${OPS#/}" ) && ok "borg extract di ${OPS#/}" || ko "borg extract fallito"
T0=$(date -d "$(sed -E "s/^$HOST-//; s/T/ /; s/\..*//" <<<"$A")" +%s)
nd=0; nl=0
while read -r line; do
  [ -n "$line" ] || continue
  f=$(sed -E 's/^Files (.+) and .+ differ$/\1/; s/^Only in ([^:]+): (.+)$/\1\/\2/' <<<"$line"); f=${f#"$R"}
  if [ -e "$f" ] && [ "$(stat -c %Y -- "$f")" -ge "$T0" ]; then nl=$((nl+1)); else nd=$((nd+1)); echo "  DIFFERENZA: $line"; fi
done < <(diff -rq --no-dereference "$OPS" "$R$OPS" 2>&1 || true)
[ "$nd" -eq 0 ] && ok "$OPS ripristinato identico all'originale (file modificati dopo il backup: $nl)" || ko "$nd differenze non spiegate"
for g in "$R$OPS" "$R$OPS/knowledge-base"; do
  [ -d "$g/.git" ] || { ko "manca $g/.git"; continue; }
  out=$(git -c safe.directory='*' -C "$g" fsck --full 2>&1) && ok "git fsck ${g#"$R"} (copia ripristinata)" || { ko "git fsck ${g#"$R"}"; echo "$out" | tail -5; }
  echo "  HEAD ripristinato: $(git -c safe.directory='*' -C "$g" log -1 --format='%h %s' | cut -c1-70)"
done
rm -rf -- "$R"; trap - EXIT; ok "cartella temporanea rimossa"

echo "== 12.4 (prima del riavvio) MONTAGGI"
fv=$(findmnt --verify 2>&1 || true); grep -E "errors|\[[EW]\]" <<<"$fv" | sed "s/^ */  /"
grep -qE '^0 parse errors, 0 errors' <<<"$fv" && ok "findmnt --verify: 0 errori" || ko "findmnt --verify segnala errori"
echo "ESITO PASSO 12 VERIFICHE=$bad"
exit $bad
