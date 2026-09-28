#!/usr/bin/env bash
# check-runner.sh — verifiche NON distruttive di un'installazione Paperclip con runner isolato (solo dati e token
# fittizi): rete del runner, proxy, API di Paperclip dal runner, SSH, isolamento.
# Parametri: RUNNER, PAPERCLIP, PROXY, DB (nomi dei container), SSH_KEY (chiave privata Paperclip→runner),
# DOCS (documentazione montata in sola lettura nel runner, predefinito /docs), reti "aic-runner" e "aic-egress-int"
# (adattare i nomi se diversi). Esempio:
#   RUNNER=ai-company-runner-1 PAPERCLIP=ai-company-paperclip-1 PROXY=ai-company-egress-proxy-1 DB=ai-company-db-1 \
#   SSH_KEY=/srv/<progetto>/app/secrets/runner_ssh_key ./check-runner.sh
#   tests/production/check-runner.sh           tutte le verifiche
#   tests/production/check-runner.sh --codex   anche Codex attraverso il proxy (invia a OpenAI una chiave FITTIZIA)
# Esito finale: "TUTTO CONFORME" oppure l'elenco delle difformità. Non modifica nulla.
set -uo pipefail
cd "$(dirname "$0")"
R=${RUNNER:-runner}; P=${PAPERCLIP:-paperclip}; X=${PROXY:-egress-proxy}; DB=${DB:-db}
SSH_KEY=${SSH_KEY:?percorso della chiave privata Paperclip→runner}
IMG=$(docker inspect -f '{{.Config.Image}}' $R); BAD=()
bad() { BAD+=("$*"); echo "  DIFFORME: $*"; }
echo "== 1. raggiungibilità dal runner (attesi solo paperclip:3100 e proxy:3128)"
PIP=$(docker inspect -f '{{(index .NetworkSettings.Networks "aic-runner").IPAddress}}' $P)
XIP=$(docker inspect -f '{{(index .NetworkSettings.Networks "aic-egress-int").IPAddress}}' $X)
T=$(RUNNER=$R PROXY=$X python3 - "$PIP" "$XIP" <<'PY'
import json, os, subprocess, sys
pip, xip = sys.argv[1], sys.argv[2]
t = []
for ip in subprocess.run(["hostname", "-I"], capture_output=True, text=True).stdout.split():
    if ":" not in ip: t.append([f"host {ip}", ip, [22, 80, 139, 443, 445, 8123]])
gw = subprocess.run(["sh", "-c", "ip route show default | awk '{print $3; exit}'"], capture_output=True, text=True).stdout.strip()
if gw: t.append([f"router {gw}", gw, [53, 80, 443]])
ids = subprocess.run(["docker", "ps", "-q"], capture_output=True, text=True).stdout.split()
for i in ids:
    info = json.loads(subprocess.run(["docker", "inspect", i], capture_output=True, text=True).stdout)[0]
    name = info["Name"].lstrip("/")
    if name == os.environ.get("RUNNER"): continue
    ports = sorted({int(p.split("/")[0]) for p in (info["Config"].get("ExposedPorts") or {})}) or [80]
    if name == os.environ.get("PROXY"): ports = [3128]
    for net, v in (info["NetworkSettings"]["Networks"] or {}).items():
        if v.get("IPAddress"): t.append([f"{name} ({net})", v["IPAddress"], ports])
        if v.get("Gateway"): t.append([f"gateway {net}", v["Gateway"], [22, 80, 443]])
t.append(["Internet 1.1.1.1", "1.1.1.1", [443]])
print(json.dumps(t))
PY
)
OUT=$(docker exec -i $R node --input-type=module - "$T" < probe.mjs)
echo "$OUT" | awk -F'\t' '{printf "  %-52s %s\n", $1, $2}'
while IFS=$'\t' read -r name open; do
  case "$name" in
    *"(aic-runner)"*) [[ "$name" == "$P "* ]] && { [ "$open" = 3100 ] || bad "paperclip non raggiungibile su 3100"; continue; } ;;
    *"(aic-egress-int)"*) [[ "$name" == "$X "* ]] && { [ "$open" = 3128 ] || bad "proxy non raggiungibile"; continue; } ;;
    "DNS esterno"*) [ "$open" = "non risolve" ] || bad "il runner risolve nomi esterni"; continue ;;
  esac
  [ "$open" = "-" ] || bad "raggiungibile: $name ($open)"
done <<< "$OUT"
echo "== 2. proxy di uscita"
PT=$(docker exec -i $R node --input-type=module - < proxytest.mjs); echo "$PT" | sed 's/^/  /'
grep -qE "^([0-9]+)/\\1 " <<< "$PT" || bad "proxy non conforme"
echo "== 3. API di Paperclip chiamata direttamente dal runner (attese negate)"
CID=$(docker exec $DB psql -U paperclip -d paperclip -Atc "select id from companies limit 1")
AT=$(docker exec -i $R node --input-type=module - "$CID" < apitest.mjs); echo "$AT" | sed 's/^/  /'
grep -vqE '^40[13] ' <<< "$AT" && bad "una chiamata diretta all'API non è stata negata"
echo "== 4. SSH verso il runner"
KH=$(mktemp); docker run --rm --network aic-runner --entrypoint ssh-keyscan "$IMG" -p 2222 -t ed25519 runner 2>/dev/null > "$KH"
echo "  chiave host: $(ssh-keygen -lf "$KH" | cut -d' ' -f2)"
S=(docker run --rm -i --network aic-runner --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$SSH_KEY:/k/id:ro" -v "$KH:/k/kh:ro" --entrypoint ssh "$IMG" -o UserKnownHostsFile=/k/kh -o StrictHostKeyChecking=yes -o BatchMode=yes -p 2222)
[ "$("${S[@]}" -i /k/id agent@runner 'echo ok' 2>&1 | tail -1)" = ok ] && echo "  chiave dedicata: accettata" || bad "chiave dedicata rifiutata"
o=$("${S[@]}" agent@runner true 2>&1); grep -q 'Permission denied' <<< "$o" && echo "  senza chiave: rifiutato" || bad "accesso senza chiave"
o=$("${S[@]}" -i /k/id root@runner true 2>&1); grep -q 'Permission denied' <<< "$o" && echo "  root: rifiutato" || bad "accesso root"
o=$("${S[@]}" -i /k/id -W paperclip:3100 agent@runner </dev/null 2>&1); grep -q 'forwarding failed' <<< "$o" && echo "  inoltro TCP: rifiutato" || bad "inoltro TCP ammesso"
rm -f "$KH"
echo "== 5. isolamento del runner"
while read -r l; do [ -n "$l" ] && bad "$l"; done < <(docker exec -e DOCS="${DOCS:-/docs}" $R sh -c 'for p in /run/secrets /paperclip /srv/ops /var/run/docker.sock; do [ -e $p ] && echo "PRESENTE $p"; done; [ -n "$(ls -A /srv 2>/dev/null)" ] && echo "CONTENUTO in /srv"; for w in "$DOCS/x" /usr/local/x /etc/x /var/lib/runner-ssh/x; do (: > "$w") 2>/dev/null && { echo "SCRIVIBILE $w"; rm -f "$w"; }; done; true')
I=$(docker inspect -f '{{.HostConfig.Privileged}} {{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CapDrop}} {{len .HostConfig.PortBindings}}' $R)
[ "$I" = "false true [ALL] 0" ] && echo "  privilegi, root in sola lettura, capability, porte: conformi" || bad "configurazione del container: $I"
echo "  cartelle di esecuzione residue: $(docker exec $R sh -c 'ls /work/.paperclip-runtime/runs 2>/dev/null | wc -l'), file auth.json: $(docker exec $R sh -c 'find /work /tmp /home/agent -name auth.json 2>/dev/null | wc -l')"
if [ "${1:-}" = --codex ]; then
  echo "== 6. Codex attraverso il proxy (chiave FITTIZIA; atteso 401)"
  docker exec $R sh -lc 'export CODEX_HOME=/tmp/cx OPENAI_API_KEY="sk-FITTIZIO$(head -c8 /dev/urandom | od -An -tx1 | tr -d " \n")"; mkdir -p /tmp/cx /tmp/cxw; cd /tmp/cxw; timeout 90 codex exec --skip-git-repo-check -s read-only ok </dev/null 2>&1 | grep -c 401; rm -rf /tmp/cx /tmp/cxw' | sed 's/^/  risposte 401: /'
fi
echo "== esito"; if [ "${#BAD[@]}" -eq 0 ]; then echo "  TUTTO CONFORME"; else printf '  %s\n' "${BAD[@]}"; exit 1; fi
