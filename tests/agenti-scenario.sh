# shellcheck shell=bash
# agenti-scenario.sh — agenti di amministrazione (0.7.0), incluso da scenario.sh dopo installa-scenario.sh.
# PROVE SIMULATE (CLI finti, nessun modello contattato):
#   A1–A4   agente della sessione: dichiarazioni doppie, vuoto, non valido, compatibilità AGENTI_CLI della VM 0.6.0
#   A5–A10  collaudo dell'agente della sessione: altri agenti senza login non bloccano; uscita non zero con testo atteso
#           (consegna 0.6.0); quota esaurita; login mancante; isolamento violato; isolamento dimostrato
#   A11–A16 ambiente e sandbox di tutti (senza login): ops-agy, impostazioni di Claude, bubblewrap, sandbox di Codex,
#           podman e immagine di Gemini CLI, esecuzione senza shell interattiva
#   A17–A18 aggiornamento (Antigravity mai da cli-update), --stato
#   A19     quick-check: ultimo esito per agente, login rilevante solo per l'agente della sessione
#   A20–A21 comando agente: scelta, login guidato del solo agente scelto, collaudo, avvio, ripiego su un altro agente
#   A22     kb sync nella sandbox di Codex distinto da un guasto reale
#   A23     ops-installa --piano con AGENTE
# PROVE REALI IN CONTAINER (rete, pacchetti e download veri; nessun login, nessuna sandbox avviabile in Docker):
#   A24–A28 i quattro agenti installati dal bootstrap, Antigravity in /opt (SHA-512), configurazioni, regole di Codex con
#           codex execpolicy, profili AppArmor validati da apparmor_parser, blocco .bash_aliases precedente aggiornato,
#           domanda finale dell'agente della sessione

echo "== A0 preparazione: utente con CLI simulati"
AG=/tmp/ag; rm -rf $AG; mkdir -p $AG/ops; chmod 0777 $AG
mkdir -p $AG/profiles/local
printf 'profile bwrap /usr/bin/bwrap flags=(attach_disconnected) {\n}\n' > $AG/profiles/ubuntu-bwrap
profile_code=$(sed -n '/^  ubuntu_bwrap=0$/,/^  if \[ "\$ubuntu_bwrap" = 1 \]; then$/p' "$PKG/bootstrap.sh" | sed '$d;s|/etc/apparmor.d/\*|/tmp/ag/profiles/*|')
BWRAP_PROFILE=$AG/profiles/ops-bwrap
eval "$profile_code"
[ "$ubuntu_bwrap" = 1 ] && pass "A0 profilo Ubuntu trovato anche con directory local: nessun duplicato" || bad "A0 rilevamento profilo Ubuntu"
mv $AG/profiles/ubuntu-bwrap $BWRAP_PROFILE
eval "$profile_code"
[ "$ubuntu_bwrap" = 0 ] && pass "A0 profilo gestito da solo non scambiato per profilo Ubuntu" || bad "A0 profilo gestito"
id agtest >/dev/null 2>&1 || useradd -m -s /bin/bash agtest
AH=/home/agtest; FB=$AH/.npm-global/bin
runuser -u agtest -- mkdir -p $FB $AH/.claude $AH/.codex/rules $AH/.gemini/antigravity-cli
# un solo programma finto per claude, gemini e agy: modi in /tmp/ag/<nome>.mode
cat > $AG/finto <<'EOF'
#!/bin/bash
n=${FINTO:-$(basename "$0")}; m=$(cat /tmp/ag/$n.mode 2>/dev/null || echo ok); echo "$n $*" >> /tmp/ag/calls
[ "${1:-}" != --settings ] || shift 2
a="$*"
case $1 in
  --version) echo "1.0.0"; exit 0 ;;
  auth) [ "$m" = noauth ] && { echo '{ "loggedIn": false }'; exit 1; }; echo '{ "loggedIn": true }'; exit 0 ;;
esac
if [ $# -eq 0 ]; then   # sessione interattiva (o login di agy): crea il token, segnala l'avvio
  [ "$n" = agy ] && { mkdir -p ~/.gemini/antigravity-cli; echo t > ~/.gemini/antigravity-cli/antigravity-oauth-token; rm -f /tmp/ag/agy.mode; }
  echo "SESSIONE $n in $(pwd)"; exit 0
fi
if [[ "$a" == *"Prova di isolamento"* ]]; then
  p=$(sed -E "s/.*touch '([^']+)'.*/\1/" <<<"$a")
  [ "$m" = leak ] && { touch "$p"; echo "fatto"; exit 0; }
  [ "$m" = muto ] && { echo "ok"; exit 0; }
  echo "touch: cannot touch '$p': Read-only file system"; exit 0
fi
case $m in
  badsmoke) echo "nessuna istruzione" ;;
  exit1) echo "AGENTS.md, PRECHECK"; exit 1 ;;
  quota) echo "Error: quota exceeded"; exit 1 ;;
  *) echo "Da /srv/ops/AGENTS.md: PRECHECK, BACKUP, MODIFICA, VERIFY" ;;
esac
EOF
cat > $FB/codex <<'EOF'
#!/bin/bash
m=$(cat /tmp/ag/codex.mode 2>/dev/null || echo ok); echo "codex $*" >> /tmp/ag/calls
case $1 in
  --version) echo "codex-cli 0.160.1" ;;
  login) [ "$1 $2" = "login status" ] && { [ "$m" = noauth ] && { echo "Not logged in"; exit 1; }; echo "Logged in using ChatGPT"; exit 0; }
         rm -f /tmp/ag/codex.mode; echo "login completato" ;;
  exec) case $m in badsmoke) echo "nessuna istruzione" ;; exit1) echo "AGENTS.md, PRECHECK"; exit 1 ;; *) echo "Da AGENTS.md: PRECHECK" ;; esac ;;
  sandbox)
    [ "$m" = nosandbox ] && { echo "bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted"; exit 1; }
    while [ "$1" != -- ]; do shift; done; shift
    if [[ "$*" == *ops-sandbox-probe* ]] && [ "$m" != sandboxwrite ]; then echo "Read-only file system"; exit 1; fi
    "$@" ;;
  "") echo "SESSIONE codex in $(pwd)" ;;
esac
EOF
cat > $FB/npm <<'EOF'
#!/bin/bash
case $1 in
  ls) echo "{\"dependencies\":{\"$(echo "$*" | awk '{print $NF}')\":{\"version\":\"1.0.0\"}}}" ;;
  view) echo "1.0.0" ;;
  *) echo "npm $*" >> /tmp/ag/calls ;;
esac
EOF
for f in bwrap podman ops-agy; do
  printf '#!/bin/bash\nm=$(cat /tmp/ag/%s.mode 2>/dev/null || echo ok); echo "%s $*" >> /tmp/ag/calls\n[ "$m" = ok ] && { echo "ok  finto"; exit 0; }; echo "KO  %s finto: $m"; exit 1\n' "$f" "$f" "$f" > $FB/$f
done
printf '#!/bin/bash\nexit 0\n' > $FB/socat
cp $AG/finto $FB/claude; cp $AG/finto $FB/gemini; cp $AG/finto $AG/agy
printf '#!/bin/bash\n[ "$1" = procs ] && exit 0\nexit 0\n' > $AG/fake-maint; : > $AG/lock
chmod 0755 $FB/* $AG/agy $AG/finto $AG/fake-maint; chmod 0644 $AG/lock; chown -R agtest:agtest $AH
runuser -u agtest -- cp "$PKG/payload/home/claude-settings.json" $AH/.claude/settings.json
runuser -u agtest -- cp "$PKG/payload/home/codex-config.toml" $AH/.codex/config.toml
runuser -u agtest -- cp "$PKG/payload/home/codex-ops.rules" $AH/.codex/rules/ops.rules
runuser -u agtest -- cp "$PKG/payload/home/antigravity-settings.json" $AH/.gemini/antigravity-cli/settings.json
runuser -u agtest -- cp "$PKG/payload/home/gemini-settings.json" $AH/.gemini/settings.json
TOKF=$AH/.gemini/antigravity-cli/antigravity-oauth-token
login_all() { runuser -u agtest -- sh -c "echo t > $TOKF; printf 'GEMINI_API_KEY=finta\n' > $AH/.gemini/.env; chmod 600 $AH/.gemini/.env $TOKF"; }
login_all
HCA=$AG/ops/host.conf; CU=$PKG/payload/ops/bin/cli-update; AGC=$PKG/payload/ops/bin/agente
hca() { printf '%s\n' "$@" > $HCA; chmod 0666 $HCA; }
modes() { rm -f $AG/*.mode $AG/calls; for kv in "$@"; do echo "${kv#*=}" > "$AG/${kv%%=*}.mode"; done; chmod 0666 $AG/*.mode 2>/dev/null; :; }
cat > $AG/gemini-check <<'EOF'
#!/bin/bash
[ "$(cat /tmp/ag/gemini-sandbox.mode 2>/dev/null || echo ok)" = ok ] || { echo 'KO sandbox nativa'; exit 1; }
echo 'OK sandbox nativa simulata'
EOF
chmod 0755 $AG/gemini-check
printf '#!/bin/bash\nexit 0\n' > $AG/claude-check; chmod 0755 $AG/claude-check
ENVV=(OPS_HOSTCONF=$HCA OPS_AGY_BIN=$AG/agy OPS_AGY_CMD=$FB/ops-agy OPS_GEMINI_CHECK=$AG/gemini-check OPS_CLAUDE_CHECK=$AG/claude-check MAINT_LOCK=$AG/lock MAINT_BIN=$AG/fake-maint)
cuv() { runuser -u agtest -- env "${ENVV[@]}" "$@" > $AG/out 2>&1; echo $?; }
calls() { cat $AG/calls 2>/dev/null; }

echo "== A1–A4 agente della sessione in host.conf (letto senza eseguirlo)"
modes; hca 'AGENTE="codex"' 'AGENTE="agy"'; rc=$(cuv $CU --verify)
[ "$rc" = 1 ] && grep -q 'AGENTE dichiarato più volte' $AG/out && ! calls | grep -q ' -p\| --print\| exec ' && pass "A1 AGENTE dichiarato due volte: esito 1, nessun agente avviato" || { bad "A1 (rc=$rc)"; cat $AG/out; }
hca 'AGENTE=""'; rc=$(cuv $CU --verify)
[ "$rc" = 1 ] && grep -q 'nessun agente della sessione' $AG/out && pass "A2 AGENTE vuoto: esito 1 con indicazione del comando agente" || { bad "A2 (rc=$rc)"; cat $AG/out; }
hca 'AGENTE="gemini2"'; rc=$(cuv $CU --verify)
[ "$rc" = 1 ] && grep -q 'AGENTE non valido' $AG/out && pass "A3 AGENTE non valido: esito 1" || { bad "A3 (rc=$rc)"; cat $AG/out; }
hca 'AGENTI_CLI="codex"'; rc=$(cuv $CU --verify)
[ "$rc" = 0 ] && grep -q 'codex: verifica OK' $AG/out && pass "A4 compatibilità: AGENTI_CLI=\"codex\" della correzione VM 0.6.0 → Codex collaudato" || { bad "A4 (rc=$rc)"; cat $AG/out; }

echo "== A5–A10 collaudo dell'agente della sessione"
modes claude=noauth gemini=badsmoke; rm -f $AH/.gemini/.env; hca 'AGENTE="agy"'; rc=$(cuv $CU --verify)
[ "$rc" = 0 ] && grep -q 'agy: verifica OK' $AG/out && grep -q 'claude: login non fatto (agente non in uso' $AG/out && grep -q 'gemini: login non fatto' $AG/out \
  && ! calls | grep -qE '^(claude -p|gemini -p)' && pass "A5 Antigravity collaudato; Claude e Gemini CLI senza login (o difettosi) non bloccano e non vengono avviati" || { bad "A5 (rc=$rc)"; cat $AG/out; calls; }
login_all
modes agy=exit1; rc=$(cuv $CU --verify)
[ "$rc" = 1 ] && grep -q 'agy: VERIFICA FALLITA: AGENTS.md non caricato o uscita diversa da 0' $AG/out && pass "A6 uscita non zero con testo atteso: fallita (correzione della consegna 0.6.0)" || { bad "A6 (rc=$rc)"; cat $AG/out; }
modes agy=quota; rc=$(cuv $CU --verify)
[ "$rc" = 1 ] && grep -q 'quota' $AG/out && pass "A7a quota esaurita: agente della sessione non utilizzabile (esito 1)" || { bad "A7a (rc=$rc)"; cat $AG/out; }
rc=$(cuv $CU --verify claude)
[ "$rc" = 0 ] && grep -q 'claude: verifica OK' $AG/out && pass "A7b con Antigravity senza quota si collauda un altro agente (--verify claude): esito 0" || { bad "A7b (rc=$rc)"; cat $AG/out; }
modes; rm -f $TOKF; rc=$(cuv $CU --verify)
[ "$rc" = 1 ] && grep -q 'agy: NON AUTENTICATO: completare il login con agente agy' $AG/out && pass "A8 Antigravity senza login: NON AUTENTICATO con l'indicazione del login" || { bad "A8 (rc=$rc)"; cat $AG/out; }
login_all; modes agy=leak; rc=$(cuv $CU --verify)
[ "$rc" = 1 ] && grep -q 'isolamento violato' $AG/out && ! ls $AH/.ops-sandbox-probe-* >/dev/null 2>&1 && pass "A9 scrittura nella home riuscita (ripiego fuori dalla sandbox): verifica fallita, file rimosso" || { bad "A9 (rc=$rc)"; cat $AG/out; }
modes; rc=$(cuv $CU --verify)
[ "$rc" = 0 ] && grep -q 'agy: isolamento dimostrato' $AG/out && pass "A10a rifiuto della sandbox riportato: isolamento dimostrato" || { bad "A10a (rc=$rc)"; cat $AG/out; }
modes agy=muto; rc=$(cuv $CU --verify)
[ "$rc" = 1 ] && grep -q 'isolamento NON DIMOSTRATO' $AG/out && pass "A10b nessun rifiuto riportato: NON DIMOSTRATO, verifica fallita" || { bad "A10b (rc=$rc)"; cat $AG/out; }

echo "== A11–A16 ambiente e sandbox dei quattro agenti (senza login)"
modes ops-agy=ko; hca 'AGENTE="codex"'; rc=$(cuv $CU --ambiente)
[ "$rc" = 1 ] && grep -q 'agy: AMBIENTE NON CONFORME: ops-agy verify' $AG/out && grep -q 'codex: ambiente OK' $AG/out && pass "A11a Antigravity non conforme (ops-agy verify): --ambiente esito 1, gli altri OK" || { bad "A11a (rc=$rc)"; cat $AG/out; }
rc=$(cuv $CU --verify)
[ "$rc" = 0 ] && grep -q 'agy: ATTENZIONE, AMBIENTE NON CONFORME (non blocca Codex CLI)' $AG/out && pass "A11b ambiente di un altro agente non conforme: ATTENZIONE, non blocca l'agente della sessione" || { bad "A11b (rc=$rc)"; cat $AG/out; }
modes; jq '.sandbox.enabled = false' "$PKG/payload/home/claude-settings.json" > $AG/cs.json; cp $AG/cs.json $AH/.claude/settings.json
rc=$(cuv $CU --ambiente claude)
[ "$rc" = 1 ] && grep -q 'claude: AMBIENTE NON CONFORME: configurazione di sandbox' $AG/out && pass "A12 Claude Code con sandbox disattivata: non conforme" || { bad "A12 (rc=$rc)"; cat $AG/out; }
runuser -u agtest -- cp "$PKG/payload/home/claude-settings.json" $AH/.claude/settings.json
modes bwrap=ko; rc=$(cuv $CU --ambiente)
[ "$rc" = 1 ] && grep -q 'claude: AMBIENTE NON CONFORME: bubblewrap' $AG/out && grep -q 'codex: AMBIENTE NON CONFORME: bubblewrap' $AG/out && grep -q 'gemini: ambiente OK' $AG/out \
  && pass "A13 bubblewrap senza namespace: Claude Code e Codex non conformi, Gemini CLI e Antigravity no" || { bad "A13 (rc=$rc)"; cat $AG/out; }
modes codex=nosandbox; rc=$(cuv $CU --ambiente codex)
[ "$rc" = 1 ] && grep -q 'la sandbox di Codex non parte' $AG/out && pass "A14a sandbox di Codex che non parte: non conforme" || { bad "A14a (rc=$rc)"; cat $AG/out; }
modes codex=sandboxwrite; rc=$(cuv $CU --ambiente codex)
[ "$rc" = 1 ] && grep -q 'scrive nella home' $AG/out && ! ls $AH/.ops-sandbox-probe-* >/dev/null 2>&1 && pass "A14b sandbox di Codex che scrive nella home: non conforme, file rimosso" || { bad "A14b (rc=$rc)"; cat $AG/out; }
modes; echo 'approval_policy = "never"' >> $AH/.codex/config.toml; rc=$(cuv $CU --ambiente codex)
[ "$rc" = 1 ] && pass "A14c Codex con approval_policy never: non conforme" || { bad "A14c (rc=$rc)"; cat $AG/out; }
runuser -u agtest -- cp "$PKG/payload/home/codex-config.toml" $AH/.codex/config.toml
modes gemini-sandbox=ko; rc=$(cuv $CU --ambiente gemini)
[ "$rc" = 1 ] && grep -q 'sandbox nativa Gemini non conforme' $AG/out && pass "A15a Gemini CLI: sandbox nativa non funzionante → non conforme" || { bad "A15a (rc=$rc)"; cat $AG/out; }
jq '.security.toolSandboxing = false' "$PKG/payload/home/gemini-settings.json" > $AG/gs.json; cp $AG/gs.json $AH/.gemini/settings.json; modes; rc=$(cuv $CU --ambiente gemini)
[ "$rc" = 1 ] && pass "A15b Gemini CLI senza sandbox: non conforme" || { bad "A15b (rc=$rc)"; cat $AG/out; }
runuser -u agtest -- cp "$PKG/payload/home/gemini-settings.json" $AH/.gemini/settings.json
jq '.toolPermission = "always-proceed"' "$PKG/payload/home/antigravity-settings.json" > $AG/as.json; cp $AG/as.json $AH/.gemini/antigravity-cli/settings.json; rc=$(cuv $CU --ambiente agy)
[ "$rc" = 1 ] && pass "A15c Antigravity con always-proceed: non conforme" || { bad "A15c (rc=$rc)"; cat $AG/out; }
runuser -u agtest -- cp "$PKG/payload/home/antigravity-settings.json" $AH/.gemini/antigravity-cli/settings.json
modes; hca 'AGENTE="gemini"'; rc=$(runuser -u agtest -- env -i HOME=$AH "${ENVV[@]}" $CU --verify > $AG/out 2>&1; echo $?)
[ "$rc" = 0 ] && grep -q 'gemini: verifica OK' $AG/out && [ "$(grep -c 'ambiente OK' $AG/out)" = 3 ] && pass "A16 esecuzione con ambiente vuoto (come il timer): quattro agenti trovati, Gemini CLI collaudato" || { bad "A16 (rc=$rc)"; cat $AG/out; }

echo "== A17–A18 aggiornamento e stato"
modes; rc=$(DRY_RUN=1 cuv $CU)
[ "$rc" = 0 ] && grep -q 'claude: 1.0.0 aggiornato' $AG/out && grep -q 'codex: 1.0.0 aggiornato' $AG/out && grep -q 'gemini: 1.0.0 aggiornato' $AG/out && ! calls | grep -q '^agy update' \
  && pass "A17 aggiornamento npm di Claude Code, Codex e Gemini CLI; Antigravity mai da cli-update (è di root)" || { bad "A17 (rc=$rc)"; cat $AG/out; }
runuser -u agtest -- env "${ENVV[@]}" $CU --stato > $AG/out 2>&1
[ "$(wc -l < $AG/out)" = 4 ] && grep -q '^gemini|Gemini CLI|1.0.0|conforme|fatto|sessione$' $AG/out && pass "A18 --stato: quattro righe, agente della sessione indicato" || { bad "A18"; cat $AG/out; }

echo "== A19 quick-check"
Q=$AG/qc; mkdir -p $Q; cp /srv/ops/host.conf $Q/host.conf; sed -i '/^AGENTE=/d; /^AGENTI_CLI=/d' $Q/host.conf; echo 'AGENTE="agy"' >> $Q/host.conf; chmod -R a+rX $Q
L=$AH/.local/state/ops/cli-update/cli-update.log; d1=$(date -u -d '-2 days' '+%F %T'); d0=$(date -u '+%F %T')
printf '%s\n' "$d1 cli-update: agy: VERIFICA FALLITA: AGENTS.md non caricato" "$d0 cli-update: agy: verifica OK (agente della sessione)" \
  "$d0 cli-update: claude: login non fatto (agente non in uso: nessun problema)" "$d0 cli-update: gemini: NON AUTENTICATO: completare il login" > $L; chown agtest $L
qc() { runuser -u agtest -- env OPS_DIR=$Q /srv/ops/bin/quick-check > $AG/out 2>&1; }
qc; ! grep -qE 'agente (agy|claude|gemini)|senza login' $AG/out && pass "A19a fallimento superato e altri agenti senza login: nessuna attenzione" || { bad "A19a"; grep -i agente $AG/out; }
echo "$d0 cli-update: agy: NON AUTENTICATO: completare il login con agente agy" >> $L; qc
grep -q 'agente della sessione senza login' $AG/out && pass "A19b agente della sessione senza login: attenzione" || { bad "A19b"; grep -i agente $AG/out; }
echo "$d0 cli-update: codex: AMBIENTE NON CONFORME: bubblewrap" >> $L; qc
grep -q 'agente codex: .*NON CONFORME' $AG/out && pass "A19c ambiente non conforme di un altro agente: attenzione" || { bad "A19c"; grep -i agente $AG/out; }
sed -i 's/^AGENTE=.*/AGENTE=""/' $Q/host.conf; qc
grep -q 'nessun agente della sessione' $AG/out && pass "A19d nessun agente della sessione: attenzione" || { bad "A19d"; grep -i agente $AG/out; }

echo "== A20–A21 comando agente"
chown agtest:agtest $AG/ops; runuser -u agtest -- git -C $AG/ops init -q -b main; hca 'HOST=x' 'AGENTE=""'; chown agtest:agtest $HCA
runuser -u agtest -- sh -c "cd $AG/ops && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm iniziale"
runuser -u agtest -- git -C $AG/ops config user.name t; runuser -u agtest -- git -C $AG/ops config user.email t@t
AGV=(OPS_DIR=$AG/ops OPS_CLI_UPDATE=$CU "${ENVV[@]}")
modes agy=noauth; rm -f $TOKF; printf 'non so\nAntigravity\n' > $AG/risposte; chmod 0644 $AG/risposte
out=$(runuser -u agtest -- env "${AGV[@]}" AGENTE_TTY=$AG/risposte $AGC 2>&1); rc=$?
grep -q 'risposta non riconosciuta' <<<"$out" && grep -q 'Login di Antigravity' <<<"$out" && grep -q 'agy: verifica OK' <<<"$out" && grep -q "SESSIONE agy in $AG/ops" <<<"$out" \
  && grep -q '^AGENTE="agy"' $HCA && runuser -u agtest -- git -C $AG/ops log -1 --format=%s | grep -q 'Antigravity CLI' && ! grep -qE 'Login di (Claude|Codex)|chiave' <<<"$out" \
  && pass "A20 agente: domanda, login guidato SOLO di Antigravity, collaudo, scelta registrata con commit, avvio in /srv/ops" || { bad "A20 (rc=$rc)"; echo "$out" | tail -20; }
modes gemini=quota; printf 'gemini\nA\nclaude\n' > $AG/risposte
out=$(runuser -u agtest -- env "${AGV[@]}" AGENTE_TTY=$AG/risposte $AGC 2>&1); rc=$?
grep -q 'Gemini CLI non è utilizzabile ora' <<<"$out" && grep -q 'SESSIONE claude' <<<"$out" && grep -q '^AGENTE="claude"' $HCA \
  && pass "A21a agente scelto non utilizzabile (quota): scelta di un altro agente, avvio" || { bad "A21a (rc=$rc)"; echo "$out" | tail -15; }
modes; out=$(runuser -u agtest -- env "${AGV[@]}" $AGC --scegli codex 2>&1)
grep -q '^AGENTE="codex"' $HCA && ! grep -q SESSIONE <<<"$out" && pass "A21b agente --scegli: solo la scelta, nessun avvio" || { bad "A21b"; echo "$out"; }
out=$(runuser -u agtest -- env "${AGV[@]}" $AGC --stato 2>&1)
[ "$(grep -cE 'Claude Code|Codex CLI|Antigravity CLI|Gemini CLI' <<<"$out")" = 4 ] && grep -q '← sessione' <<<"$out" && pass "A21c agente --stato: quattro agenti, nessuna modifica" || { bad "A21c"; echo "$out"; }

: > $AG/vuoto; chmod 0644 $AG/vuoto
out=$(runuser -u agtest -- env "${AGV[@]}" AGENTE_TTY=$AG/vuoto $AGC --prepara codex 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q 'codex: verifica OK' <<<"$out" && ! grep -q SESSIONE <<<"$out" && pass "A21 preparazione agente senza aprire la chat" || { bad "A21 prepara (rc=$rc)"; echo "$out"; }

rc=$(runuser -u agtest -- env "${AGV[@]}" AGENTE_TTY=$AG/vuoto timeout 60 $AGC > $AG/out 2>&1; echo $?)
[ "$rc" = 2 ] && grep -q 'nessuna risposta' $AG/out && pass "A21d input terminato: agente esce (esito 2), nessun ciclo senza fine" || { bad "A21d (rc=$rc)"; tail -3 $AG/out; }

tn "A21e nessun 'exec N<… 2>/dev/null' (chiuderebbe lo stderr di tutto il programma: domande invisibili)" \
  bash -c "grep -nE '^[[:space:]]*exec [0-9]+[<>][^;}]*2>/dev/null' $PKG/bootstrap.sh $PKG/payload/ops/bin/* $PKG/payload/ops/maint/ops-agy $PKG/payload/ops/docs/bootstrap/ops-installa"

echo "== A22 kb sync: sandbox dell'agente o guasto reale"
if [ -d /srv/ops/knowledge-base/.git ] && grep -q '^KB_REMOTE="/kbremote.git"' /srv/ops/kb.conf; then
  mv /kbremote.git /kbremote.via
  out=$(runuser -u tester -- env CODEX_SANDBOX_NETWORK_DISABLED=1 /srv/ops/bin/kb sync 2>&1); rc=$?
  [ "$rc" = 0 ] && grep -q 'SANDBOX' <<<"$out" && grep -q 'non un guasto' <<<"$out" && ! grep -q 'sincronizzata' <<<"$out" \
    && pass "A22a dentro la sandbox di Codex: limite della sandbox dichiarato, copia locale" || { bad "A22a (rc=$rc)"; echo "$out"; }
  out=$(runuser -u tester -- /srv/ops/bin/kb sync 2>&1); rc=$?
  [ "$rc" = 0 ] && grep -q 'repository non raggiungibile' <<<"$out" && ! grep -q 'SANDBOX' <<<"$out" && ! grep -q 'sincronizzata' <<<"$out" \
    && pass "A22b fuori dalla sandbox: guasto reale (esito 0 ma nessuna riga 'sincronizzata')" || { bad "A22b (rc=$rc)"; echo "$out"; }
  mv /kbremote.via /kbremote.git
  out=$(runuser -u tester -- /srv/ops/bin/kb sync 2>&1) && grep -q '^sincronizzata' <<<"$out" && pass "A22c repository raggiungibile: 'sincronizzata'" || { bad "A22c"; echo "$out"; }
else bad "A22 prerequisito: KB di prova /kbremote.git non collegata"; fi

echo "== A23 ops-installa --piano con AGENTE"
cp -p /srv/ops/host.conf $AG/hc.salvato
runuser -u tester -- sed -i 's|^AGENTE=.*|AGENTE="gemini2"|' /srv/ops/host.conf
out=$(runuser -u tester -- /usr/local/sbin/ops-installa --piano 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q 'AGENTE non valido: gemini2' <<<"$out" && pass "A23a --piano: AGENTE non valido tra i parametri da completare" || { bad "A23a (rc=$rc)"; echo "$out" | tail -6; }
runuser -u tester -- sed -i 's|^AGENTE=.*|AGENTE=""|' /srv/ops/host.conf
out=$(runuser -u tester -- /usr/local/sbin/ops-installa --piano 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q 'AGENTE vuoto: agente della sessione da scegliere con il comando agente' <<<"$out" && pass "A23b --piano: AGENTE vuoto segnalato" || { bad "A23b (rc=$rc)"; echo "$out" | tail -6; }
runuser -u tester -- sed -i 's|^AGENTE=.*|AGENTE="agy"|' /srv/ops/host.conf
out=$(runuser -u tester -- /usr/local/sbin/ops-installa --piano 2>&1)
grep -q '^Agente della sessione (collaudo operativo in 12.7.*: agy' <<<"$out" && pass "A23c --piano mostra l'agente della sessione" || { bad "A23c"; echo "$out" | head -5; }
cp -p $AG/hc.salvato /srv/ops/host.conf

echo "== A24 REALE: i quattro agenti installati dal bootstrap (T3)"
TH=/home/tester; TP="$TH/.npm-global/bin:/usr/bin:/bin"
for a in claude codex gemini; do t "A24 $a eseguibile senza shell interattiva" runuser -u tester -- env -i HOME=$TH PATH="$TP" $a --version; done
t "A24 Antigravity eseguibile dall'amministratore senza shell interattiva" runuser -u tester -- env -i HOME=$TH PATH="$TP" AGY_CLI_DISABLE_AUTO_UPDATE=true /opt/ops-agenti/antigravity/agy --version
t "A24 Antigravity di root (root:root 755) in /opt/ops-agenti, non modificabile dall'amministratore" bash -c "for p in /opt/ops-agenti /opt/ops-agenti/antigravity /opt/ops-agenti/antigravity/agy; do [ \"\$(stat -c '%U:%G %a' \$p)\" = 'root:root 755' ] || exit 1; done; ! runuser -u tester -- sh -c ': >> /opt/ops-agenti/antigravity/agy' 2>/dev/null"
t "A24 SHA-512 di Antigravity verificato (log di ops-agy)" grep -q 'SHA-512 verificato' /var/log/ops-agy.log
tn "A24 nessuna copia di agy nella home né modifiche a PATH e profili" bash -c "[ -e $TH/.local/bin/agy ] || grep -qi antigravity $TH/.bashrc $TH/.profile"
t "A24 ops-agy verify (container: restrizione dei namespace non attiva, profilo non necessario)" runuser -u tester -- /usr/local/sbin/ops-agy verify
t "A24 componenti delle sandbox installati (bubblewrap, socat)" bash -c "for p in bubblewrap socat; do dpkg-query -W -f='\${db:Status-Abbrev}' \$p | grep -q '^ii' || exit 1; done"
t "A24 Claude Code: sandbox attiva, nessuna uscita automatica, sudo negato" jq -e '.sandbox.enabled and .sandbox.failIfUnavailable and (.sandbox.allowUnsandboxedCommands == false) and (.permissions.deny | index("Bash(sudo *)"))' $TH/.claude/settings.json
t "A24 Antigravity: sandbox del terminale attiva, proceed-in-sandbox, sudo negato" jq -e '.enableTerminalSandbox and .toolPermission == "proceed-in-sandbox" and (.permissions.deny | index("command(sudo *)"))' $TH/.gemini/antigravity-cli/settings.json
t "A24 Gemini CLI: sandbox nativa, chiave API, YOLO disabilitato, nessun aggiornamento automatico" jq -e '.tools.sandbox == false and .security.toolSandboxing == true and .security.disableYoloMode == true and .security.auth.selectedType == "gemini-api-key" and .general.enableAutoUpdate == false' $TH/.gemini/settings.json
t "A24 Codex: config 0600 workspace-write / on-request" bash -c "[ \"\$(stat -c %a $TH/.codex/config.toml)\" = 600 ] && grep -qx 'sandbox_mode = \"workspace-write\"' $TH/.codex/config.toml && grep -qx 'approval_policy = \"on-request\"' $TH/.codex/config.toml"
t "A24 AGENTS.md per Gemini CLI (context.fileName del progetto)" jq -e '.context.fileName == "AGENTS.md"' /srv/ops/.gemini/settings.json
CXP() { runuser -u tester -- env -i HOME=$TH PATH="$TP" codex execpolicy check --rules $TH/.codex/rules/ops.rules -- "$@" 2>/dev/null | jq -r '.decision // "nessuna"'; }
ok_rules=1
for c in "/srv/ops/bin/quick-check" "/srv/ops/bin/quick-check --gate" "/srv/ops/bin/kb sync" "/srv/ops/bin/kb status" "/srv/ops/bin/cli-update --verify" \
         "git add -A" "git commit -m x" "git -C /srv/ops commit -m x" "systemctl status ssh" "journalctl -p err --since -24h"; do
  # shellcheck disable=SC2086
  [ "$(CXP $c)" = allow ] || { ok_rules=0; echo "   atteso allow: $c → $(CXP $c)"; }
done
for c in "/srv/ops/bin/kb publish RECORD-x" "/srv/ops/bin/kb token" "git push" "git -c core.hooksPath=/tmp commit -m x" "systemctl restart ssh" \
         "rm -rf /srv/ops" "/srv/ops/bin/cli-update" "bash -c id"; do
  # shellcheck disable=SC2086
  [ "$(CXP $c)" = nessuna ] || { ok_rules=0; echo "   atteso nessuna regola: $c → $(CXP $c)"; }
done
[ "$(CXP sudo ops-installa)" = forbidden ] || { ok_rules=0; echo "   atteso forbidden: sudo"; }
[ "$ok_rules" = 1 ] && pass "A25 regole di Codex (codex execpolicy check reale): ordinari consentiti, resto protetto, sudo vietato" || bad "A25 regole di Codex"
for p in agy bwrap; do
  /usr/local/sbin/ops-agy profilo $p > $AG/prof-$p
  if apparmor_parser -Q -K $AG/prof-$p >/dev/null 2>&1; then pass "A26 profilo AppArmor ops-$p valido (apparmor_parser, solo analisi)"; else bad "A26 profilo ops-$p"; apparmor_parser -Q -K $AG/prof-$p; fi
done
grep -q "ops-agy $(printf '%s' /opt/ops-agenti/antigravity/agy) flags=(unconfined)" $AG/prof-agy && grep -qx '  userns,' $AG/prof-agy \
  && pass "A26 profilo ops-agy mirato al solo binario di root (userns)" || bad "A26 contenuto del profilo ops-agy"
out=$(runuser -u tester -- /srv/ops/bin/cli-update --ambiente 2>&1); echo "$out" | sed 's/^/   (container) /'
grep -q 'agy: ambiente OK' <<<"$out" && pass "A26b ambiente di Antigravity conforme anche in container" || bad "A26b ambiente di Antigravity"

# Ripresa prima del login: prova isolata, nessun sudo/modello.
mkdir -p "$AG/ops/docs/bootstrap"
printf 'STATO: IN CORSO\n' > "$AG/ops/docs/bootstrap/avanzamento.md"
printf 'AGENTI_LOGIN="dopo-configurazione"\n' >> "$HCA"
printf '#!/bin/bash\necho CONFIGURA_SERVER_RIPRESA\n' > "$AG/fake-configura"
chmod 0755 "$AG/fake-configura"
: > "$AG/calls"
out=$(runuser -u agtest -- env "${AGV[@]}" OPS_CONFIGURA_CMD="$AG/fake-configura" "$AGC" claude 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q CONFIGURA_SERVER_RIPRESA <<< "$out" && [ ! -s "$AG/calls" ] \
  && pass "A26b dopo riavvio: agente riprende prima di login, collaudo o chat" || { bad "A26b ripresa prima login"; echo "$out"; }
printf 'STATO: COMPLETATO CON ESCLUSIONI\n' > "$AG/ops/docs/bootstrap/avanzamento.md"
printf 'Codice finale procedura: 7\n' > "$AG/ops/docs/bootstrap/esito-configurazione.md"
out=$(runuser -u agtest -- env "${AGV[@]}" OPS_CONFIGURA_CMD="$AG/fake-configura" "$AGC" claude 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q CONFIGURA_SERVER_RIPRESA <<< "$out" && [ ! -s "$AG/calls" ] \
  && pass "A26c KB finale fallita: nessun login/chat prima della correzione" || { bad "A26c guardia KB finale"; echo "$out"; }
sed -i '/^AGENTI_LOGIN=/d' "$HCA"
rm "$AG/ops/docs/bootstrap/avanzamento.md" "$AG/ops/docs/bootstrap/esito-configurazione.md"

echo "== A27 blocco ~/.bash_aliases della 0.6.0 aggiornato senza conflitto"
cat > $AG/blocco-060 <<'EOF'
# >>> ops: strumenti di amministrazione (gestito da setup-server-linux; non modificare tra i marcatori) >>>
# Gli strumenti partono sempre in /srv/ops (istruzioni: /srv/ops/AGENTS.md). Sottoprocesso ( ... ): alla fine
# la shell resta nella directory di partenza. Binario originale: command claude|codex|gemini
case ":$PATH:" in *":$HOME/.npm-global/bin:"*) ;; *) PATH="$HOME/.npm-global/bin:$PATH" ;; esac
unalias claude codex gemini agy 2>/dev/null
claude() { ( cd /srv/ops && command claude "$@" ); }
codex()  { ( cd /srv/ops && command codex "$@" ); }
gemini() { ( cd /srv/ops && command gemini "$@" ); }
agy()    { ( cd /srv/ops && AGY_CLI_DISABLE_AUTO_UPDATE=true "$HOME/.local/bin/agy" "$@" ); }
# Aggiornamenti dei CLI: solo tramite /srv/ops/bin/cli-update (timer settimanale), non in background.
export AGY_CLI_DISABLE_AUTO_UPDATE=true
# <<< ops <<<
EOF
[ "$(sha256sum < $AG/blocco-060 | cut -d' ' -f1)" = f479cdbe7662d584c3c4877814223315c5ab6d490dab97e34a11ba4b47a9a458 ] && pass "A27a blocco di prova identico a quello delle versioni 0.1.0–0.6.0" || bad "A27a impronta del blocco 0.6.0"
BA=$TH/.bash_aliases; cp -p $BA $AG/ba.salvato
{ echo "alias ll='ls -l'"; echo; cat $AG/blocco-060; echo "# riga dopo il blocco"; } > $BA; chown tester:tester $BA
bash "$PKG/bootstrap.sh" --admin tester "${KBARGS[@]}" > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'blocco ops di ~/.bash_aliases aggiornato' /tmp/out.txt && grep -q "^alias ll='ls -l'" $BA && grep -q '^# riga dopo il blocco' $BA \
  && sed -n '/^# >>> ops/,/^# <<< ops/p' $BA | cmp -s - "$PKG/payload/home/bash_aliases.block" && ls $BA.bak-* >/dev/null 2>&1 \
  && pass "A27b bootstrap: blocco precedente sostituito tra i marcatori, resto del file e copia conservati" || { bad "A27b (rc=$rc)"; tail -8 /tmp/out.txt; cat $BA; }
t "A27c funzione agente e agy da /opt nelle shell interattive" bash -c "runuser -u tester -- bash -ic 'type agente; type agy' 2>/dev/null | grep -q /opt/ops-agenti/antigravity/agy"
cp -p $AG/ba.salvato $BA; rm -f $BA.bak-*

echo "== A28 domanda finale: con quale agente avviare la sessione"
runuser -u tester -- sed -i 's|^AGENTE=.*|AGENTE=""|' /srv/ops/host.conf; runuser -u tester -- git -C /srv/ops commit -qam 'prova: AGENTE vuoto'
printf 'boh\nAntigravity\n' > $AG/risposte; chmod 0644 $AG/risposte
AGENTE_TTY=$AG/risposte AGENTE_TTY_OUT=$AG/domande bash "$PKG/bootstrap.sh" --admin tester "${KBARGS[@]}" > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'Con quale agente vuoi avviare la sessione? Claude Code / Codex CLI / Antigravity CLI / Gemini CLI' $AG/domande && grep -q 'risposta non riconosciuta' $AG/domande \
  && grep -q '^AGENTE="agy"' /srv/ops/host.conf && runuser -u tester -- git -C /srv/ops log -1 --format=%s | grep -q 'Antigravity CLI' && grep -q 'configura-server' /tmp/out.txt \
  && pass "A28a domanda dopo l'installazione: quattro nomi distinti, risposta registrata con commit, prossimo passo agente" || { bad "A28a (rc=$rc)"; tail -10 /tmp/out.txt; cat $AG/domande; }
bash "$PKG/bootstrap.sh" --admin tester "${KBARGS[@]}" < /dev/null > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && ! grep -q 'Con quale agente' /tmp/out.txt && grep -q 'Antigravity CLI' /tmp/out.txt && pass "A28b rieseguito: nessuna nuova domanda, nessuna reinstallazione" || { bad "A28b (rc=$rc)"; tail -5 /tmp/out.txt; }
head1=$(runuser -u tester -- git -C /srv/ops rev-parse HEAD)
bash "$PKG/bootstrap.sh" --admin tester --agente gpt "${KBARGS[@]}" > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 3 ] && grep -q -- '--agente: claude, codex, agy' /tmp/out.txt && [ "$(runuser -u tester -- git -C /srv/ops rev-parse HEAD)" = "$head1" ] && pass "A28c --agente non valido: fermo prima di ogni modifica" || { bad "A28c (rc=$rc)"; tail -3 /tmp/out.txt; }
t "repository di prova pulito dopo A28" bash -c "[ -z \"\$(runuser -u tester -- git -C /srv/ops status --porcelain)\" ]"
rm -rf $AG

# Regressioni del collaudo reale Antigravity, 2026-10-11.
t "A29 regole Antigravity valide, workspace scrivibile e fstab leggibile" jq -e '.enableTerminalSandbox == true and (.permissions.allow | index("write_file(/srv/ops)")) and (.permissions.allow | index("read_file(/etc/fstab)")) and (.permissions.deny | index("command(sudo *)")) and ([.permissions.allow[], .permissions.deny[]] | all(startswith("unsandboxed(") | not))' $TH/.gemini/antigravity-cli/settings.json
t "A29 timeout Antigravity resta nel gruppo del terminale e forza arresto" grep -Fq 'timeout --foreground --kill-after=10s 300 "$AGY"' /srv/ops/bin/cli-update

# Il diagnostico non accetta installazione, shell, sudo o argomenti extra.
t "A30 diagnostico host root non modificabile dall'amministratore" bash -c '[ "$(stat -c "%U %a" /usr/local/bin/ops-host-check)" = "root 755" ] && [ "$(stat -c "%U %a" /usr/local/lib/ops-bootstrap/rileva-parametri.sh)" = "root 644" ]'
for op in --scrivi --rollback bash; do
  tn "A30 diagnostico rifiuta $op" runuser -u tester -- /usr/local/bin/ops-host-check "$op"
done
tn "A30 diagnostico rifiuta argomenti aggiuntivi" runuser -u tester -- /usr/local/bin/ops-host-check --piano extra
t "A30 regole permettono soltanto rilevamento e piano diagnostici" jq -e '(.permissions.allow | index("command(/usr/local/bin/ops-host-check --rileva)")) and (.permissions.allow | index("command(/usr/local/bin/ops-host-check --piano)")) and ([.permissions.allow[]] | all(. != "command(ip)" and . != "command(/usr/local/sbin/ops-installa)"))' $TH/.gemini/antigravity-cli/settings.json
