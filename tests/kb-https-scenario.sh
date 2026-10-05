#!/usr/bin/env bash
# kb-https-scenario.sh — collaudo SIMULATO del collegamento facoltativo della Knowledge Base via HTTPS (0.6.0), dentro il
# container di scenario.sh dopo il bootstrap (amministratore "tester"). Usa pass/bad/t/tn di scenario.sh.
# Server Git HTTPS locale (tests/kb-https-server.py) con certificato autofirmato reso fidato nel container; token
# FITTIZI generati qui (nessuna credenziale reale, nessun accesso a GitHub). Le prove reali su GitHub restano da fare.
KB=/srv/ops/bin/kb
H=https://kb.test:8443
TOK1="github_pat_PROVA$(head -c 20 /dev/urandom | od -An -tx1 | tr -d ' \n')"
TOK2="github_pat_NUOVO$(head -c 20 /dev/urandom | od -An -tx1 | tr -d ' \n')"
BADTOK="github_pat_SBAGLIATO0000000000000000000000"

echo "== K0 preparazione: server Git HTTPS di prova con token fittizi"
apt-get install -y -qq openssl python3 cron >/dev/null 2>&1
S=/tmp/kbsrv; rm -rf $S; mkdir -p $S/git/pubblico $S/git/privato
git clone -q --bare /tmp/kbsrc $S/git/pubblico/kb.git; git clone -q --bare /tmp/kbsrc $S/git/privato/kb.git
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=kb.test" -addext "subjectAltName=DNS:kb.test" \
  -keyout $S/key.pem -out $S/cert.pem >/dev/null 2>&1
cp $S/cert.pem /usr/local/share/ca-certificates/kb-test.crt; update-ca-certificates >/dev/null 2>&1
grep -q ' kb.test$' /etc/hosts || echo "127.0.0.1 kb.test" >> /etc/hosts
printf '%s\n' "$TOK1" > $S/token; : > $S/log
python3 "$PKG/tests/kb-https-server.py" $S/git $S/cert.pem $S/key.pem $S/token $S/log 8443 > $S/server.out 2>&1 &
SRVPID=$!; sleep 1
git ls-remote "$H/pubblico/kb.git" >/dev/null 2>&1 && pass "server HTTPS di prova: repository pubblico leggibile" || { bad "server HTTPS di prova"; cat $S/server.out; }
GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote "$H/privato/kb.git" >/dev/null 2>&1 && bad "privato leggibile senza token" || pass "server HTTPS di prova: privato rifiutato senza token"

# configurazione kb separata (stessa copia di bin/kb della foundation; KB_CONF di prova, mai quella reale)
T=/tmp/kbt
newconf() {
  rm -rf $T; mkdir -p $T; chown tester:tester $T
  runuser -u tester -- rm -rf /home/tester/.config/ops-kb
  printf 'KB_DIR=%s/knowledge-base\nKB_SCELTA=""\nKB_REMOTE=""\nKB_BRANCH=main\nKB_SERVER_ID=testsrv\nKB_TOKEN_FILE=""\nKB_SSH_KEY=""\n' $T > $T/kb.conf
  chown tester:tester $T/kb.conf
}
kbt() {  # kbt "risposte" comando…: kb come amministratore, risposte da file al posto del terminale
  printf "$1" > $T/risposte; chown tester:tester $T/risposte; shift
  runuser -u tester -- env HOME=/home/tester KB_CONF=$T/kb.conf KB_TTY=$T/risposte $KB "$@" > $T/out.txt 2>&1; echo $?
}
cval() { awk -v k="$1" 'index($0, k "=") == 1 {v = substr($0, length(k) + 2); gsub(/"/, "", v); print v}' $T/kb.conf; }
TF=/home/tester/.config/ops-kb/token
nosecret() {  # il token fittizio non deve comparire in: configurazioni, copia, log, crontab, foundation
  local hit
  hit=$( { grep -rlF -e "$TOK1" -e "$TOK2" $T/kb.conf $T/knowledge-base/.git/config /var/log/ops-bootstrap.log $S/log 2>/dev/null
           runuser -u tester -- crontab -l 2>/dev/null | grep -lF -e "$TOK1" -e "$TOK2"
           runuser -u tester -- git -C /srv/ops log -p 2>/dev/null | grep -lF -e "$TOK1" -e "$TOK2"
           grep -lF -e "$TOK1" -e "$TOK2" /home/tester/.gitconfig /home/tester/.git-credentials 2>/dev/null; } || true)
  [ -z "$hit" ]
}

echo "== K1 nessuna Knowledge Base (risposta N; nessun terminale)"
newconf; rc=$(kbt 'N\n' collega)
[ "$rc" = 0 ] && [ "$(cval KB_SCELTA)" = no ] && grep -q 'KB non configurata per scelta' $T/out.txt && pass "N: KB non configurata per scelta (esito 0, scelta in kb.conf)" || { bad "risposta N (rc=$rc)"; cat $T/out.txt; }
rc=$(kbt '' sync); [ "$rc" = 0 ] && grep -q 'non configurata per scelta' $T/out.txt && pass "kb sync senza KB: lo dice ed esce con 0" || { bad "sync senza KB (rc=$rc)"; cat $T/out.txt; }
rc=$(kbt '' status); [ "$rc" = 0 ] && pass "kb status senza KB: esito 0" || bad "status senza KB (rc=$rc)"
newconf; rc=$(runuser -u tester -- env HOME=/home/tester KB_CONF=$T/kb.conf KB_TTY=/nonesiste $KB collega > $T/out.txt 2>&1; echo $?)
[ "$rc" = 4 ] && [ -z "$(cval KB_SCELTA)" ] && pass "senza terminale: nessuna scelta registrata, esito 4 (la domanda tornerà)" || { bad "senza terminale (rc=$rc)"; cat $T/out.txt; }

echo "== K2 repository pubblico (nessuna credenziale)"
newconf; rc=$(kbt "S\n$H/pubblico/kb.git\n" collega)
[ "$rc" = 0 ] && [ -d $T/knowledge-base/.git ] && [ "$(cval KB_REMOTE)" = "$H/pubblico/kb.git" ] && [ -z "$(cval KB_TOKEN_FILE)" ] && [ ! -e $TF ] \
  && grep -q 'repository pubblico, senza credenziali' $T/out.txt && pass "pubblico: scaricato senza token, nessun file di credenziale" || { bad "pubblico (rc=$rc)"; cat $T/out.txt; }
runuser -u tester -- crontab -l 2>/dev/null | grep -q "$KB sync --quiet" && pass "sincronizzazione periodica nel crontab dell'amministratore" || bad "crontab non configurato"
rc=$(kbt '' collega); [ "$rc" = 0 ] && grep -q 'già collegata' $T/out.txt && pass "kb collega su KB già collegata: nessuna domanda ripetuta" || bad "collega ripetuto (rc=$rc)"
rc=$(kbt '' publish RECORD-20260101-testsrv-aaaaaa); [ "$rc" != 0 ] && grep -q 'sola lettura' $T/out.txt && pass "kb publish via HTTPS rifiutato (lettura e scrittura separate)" || { bad "publish via HTTPS (rc=$rc)"; cat $T/out.txt; }

echo "== K3 repository privato con token valido"
newconf; rc=$(kbt "S\n$H/privato/kb.git\n$TOK1\n" collega)
[ "$rc" = 0 ] && [ -d $T/knowledge-base/.git ] && [ "$(cval KB_TOKEN_FILE)" = "$TF" ] && grep -q 'Il repository richiede autenticazione' $T/out.txt \
  && pass "privato: prima senza credenziali, poi token (input nascosto) e copia scaricata" || { bad "privato (rc=$rc)"; cat $T/out.txt; }
[ "$(stat -c '%U %a' $TF)" = "tester 600" ] && [ "$(stat -c '%U %a' $(dirname $TF))" = "tester 700" ] && pass "token in ~/.config/ops-kb: cartella 0700, file 0600, dell'amministratore" || bad "permessi del token: $(stat -c '%U %a' $TF $(dirname $TF))"
nosecret && pass "token assente da kb.conf, config della copia, crontab, log, foundation, credenziali globali di git" || bad "token trovato in un file o log"
grep -qF "$TOK1" $S/log && bad "token nel registro delle richieste (URL)" || pass "token mai negli URL delle richieste"
! grep -q '@' <<<"$(cval KB_REMOTE)" && pass "URL senza credenziali" || bad "credenziali nell'URL"
printf 'protocol=https\nhost=altro.example\n\n' | runuser -u tester -- env HOME=/home/tester KB_CONF=$T/kb.conf $KB credenziale get > $T/cred.txt
[ ! -s $T/cred.txt ] && pass "helper: nessuna credenziale per un host diverso da quello della KB" || bad "helper ha risposto a un altro host"

echo "== K4 sincronizzazione successiva (come dal cron: nessun terminale, nessuna domanda)"
git clone -q $S/git/privato/kb.git $S/w && (cd $S/w && mkdir -p records/RECORD-20260102-altro-bbbbbb && echo prova > records/RECORD-20260102-altro-bbbbbb/RECORD.md \
  && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm "record di prova" && git push -q origin HEAD:main) && rm -rf $S/w
out=$(runuser -u tester -- env -i HOME=/home/tester PATH=/usr/bin:/bin KB_CONF=$T/kb.conf GIT_TRACE=1 $KB sync --quiet 2>&1); rc=$?
[ "$rc" = 0 ] && [ -f $T/knowledge-base/records/RECORD-20260102-altro-bbbbbb/RECORD.md ] && pass "kb sync senza terminale: nuovo record recuperato con il token salvato" || { bad "sync con token (rc=$rc)"; tail -5 <<<"$out"; }
grep -qF "$TOK1" <<<"$out" && bad "token negli argomenti dei processi (GIT_TRACE)" || pass "token mai negli argomenti dei processi git (GIT_TRACE)"

echo "== K5 token revocato o scaduto: copia locale conservata, problema segnalato, gestione non interrotta"
printf '%s\n' "$TOK2" > $S/token   # il server ora accetta solo il nuovo token: il vecchio è "revocato"
head0=$(git -C $T/knowledge-base rev-parse HEAD)
rc=$(kbt '' sync)
[ "$rc" = 0 ] && grep -q 'ACCESSO NEGATO alla Knowledge Base' $T/out.txt && grep -q 'kb token' $T/out.txt && [ "$(git -C $T/knowledge-base rev-parse HEAD)" = "$head0" ] \
  && pass "token revocato: esito 0, ACCESSO NEGATO con l'istruzione, copia locale intatta" || { bad "token revocato (rc=$rc)"; cat $T/out.txt; }
kbt '' status >/dev/null; grep -q 'ULTIMO ERRORE: .*accesso negato' $T/out.txt && pass "kb status mostra l'ultimo errore" || { bad "status dopo errore"; cat $T/out.txt; }

echo "== K6 sostituzione del token (kb token)"
h0=$(sha256sum < $TF)
rc=$(kbt "$BADTOK\n" token)
[ "$rc" != 0 ] && [ "$(sha256sum < $TF)" = "$h0" ] && grep -q 'credenziale precedente invariata' $T/out.txt && pass "nuovo token errato: rifiutato, token precedente invariato" || { bad "token errato (rc=$rc)"; cat $T/out.txt; }
rc=$(kbt "$TOK2\n" token)
[ "$rc" = 0 ] && [ "$(sha256sum < $TF)" != "$h0" ] && [ "$(stat -c %a $TF)" = 600 ] && grep -q 'sincronizzata' $T/out.txt && [ ! -e $T/knowledge-base/.git/kb-errore ] \
  && pass "nuovo token verificato, salvato 0600, sincronizzazione ripristinata, errore azzerato" || { bad "sostituzione (rc=$rc)"; cat $T/out.txt; }
nosecret && pass "nessuna traccia dei token dopo la sostituzione" || bad "token trovato dopo la sostituzione"
ls -A $(dirname $TF) | grep -q '^\.token\.' && bad "file temporanei del token rimasti" || pass "nessun file temporaneo del token rimasto"

echo "== K7 accesso fallito: correzione, nuovo tentativo, rinuncia"
newconf; rc=$(kbt "S\n$H/privato/kb.git\n$BADTOK\n2\n$TOK2\n" collega)
[ "$rc" = 0 ] && [ -d $T/knowledge-base/.git ] && grep -q 'Accesso con il token non riuscito' $T/out.txt && pass "token errato → reinserimento → collegata" || { bad "riprova del token (rc=$rc)"; cat $T/out.txt; }
newconf; rc=$(kbt "S\n$H/nonesiste/kb.git\n$TOK2\n1\n$H/privato/kb.git\n$TOK2\n" collega)
[ "$rc" = 0 ] && [ "$(cval KB_REMOTE)" = "$H/privato/kb.git" ] && pass "URL errato → correzione dell'URL → collegata" || { bad "correzione URL (rc=$rc)"; cat $T/out.txt; }
newconf; rc=$(kbt "S\nhttps://utente:$BADTOK@kb.test:8443/privato/kb.git\n$H/pubblico/kb.git\n" collega)
[ "$rc" = 0 ] && grep -q 'senza credenziali nell.URL' $T/out.txt && ! grep -q "$BADTOK" $T/kb.conf && pass "URL con credenziali rifiutato, poi URL corretto" || { bad "URL con credenziali (rc=$rc)"; cat $T/out.txt; }
newconf; printf '%s\n' "$TOK2" > $S/token.salvato; : > $S/token   # server momentaneamente irraggiungibile per il privato
rc=$(kbt "S\n$H/privato/kb.git\n$TOK2\n3\n4\n" collega)
[ "$rc" = 0 ] && [ "$(cval KB_SCELTA)" = no ] && [ -z "$(cval KB_REMOTE)" ] && [ ! -d $T/knowledge-base ] && [ ! -e $TF ] \
  && pass "accesso fallito → riprova → rinuncia: KB non configurata per scelta, nessun token salvato" || { bad "rinuncia (rc=$rc)"; cat $T/out.txt; }
cp $S/token.salvato $S/token

echo "== K8 bootstrap: domande all'avvio, nessuna ripetizione, nessun collegamento predefinito"
grep -q 'filippobrundia/server-knowledge-base' "$PKG/bootstrap.sh" "$PKG/payload/ops/kb.conf.tmpl" "$PKG/install.sh" && bad "repository KB predefinito nel pacchetto" || pass "nessun repository KB predefinito nel pacchetto"
mv /srv/ops /srv/ops.k8; cp -p /var/lib/ops-bootstrap/pacchetto.manifest /tmp/ref.k8; runuser -u tester -- crontab -r 2>/dev/null || true
bash "$PKG/bootstrap.sh" --admin tester --no-kb > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'KB non configurata per scelta' /tmp/out.txt && grep -q '^KB_SCELTA="no"' /srv/ops/kb.conf && pass "bootstrap --no-kb: completato (esito 0), KB non configurata per scelta" || { bad "bootstrap --no-kb (rc=$rc)"; tail -8 /tmp/out.txt; }
bash "$PKG/bootstrap.sh" --admin tester > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'KB non configurata per scelta (registrata in kb.conf' /tmp/out.txt && pass "seconda esecuzione: la domanda non viene ripetuta" || { bad "seconda esecuzione (rc=$rc)"; tail -5 /tmp/out.txt; }
runuser -u tester -- /srv/ops/bin/kb sync > /tmp/out.txt 2>&1 && grep -q 'non configurata per scelta' /tmp/out.txt && pass "SYNC BEFORE WORK senza KB: esito 0" || bad "kb sync dopo --no-kb"
rm -rf /srv/ops
printf "S\n$H/privato/kb.git\n$TOK2\n" > /tmp/risposte; chmod 0644 /tmp/risposte
KB_TTY=/tmp/risposte bash "$PKG/bootstrap.sh" --admin tester > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && [ -d /srv/ops/knowledge-base/.git ] && grep -q '^KB_SCELTA="si"' /srv/ops/kb.conf && grep -q 'Knowledge Base disponibile' /tmp/out.txt \
  && pass "bootstrap con KB privata: domanda, URL, token, copia scaricata, foundation completa (esito 0)" || { bad "bootstrap con KB privata (rc=$rc)"; tail -12 /tmp/out.txt; }
T=/srv/ops; nosecret && ! grep -qF "$TOK2" /tmp/out.txt && pass "bootstrap: token assente da log, kb.conf, commit della foundation e crontab" || bad "token trovato dopo il bootstrap"
[ ! -e /home/tester/.ssh/kb_deploy ] || [ /home/tester/.ssh/kb_deploy -ot /tmp/risposte ] && pass "nessuna nuova deploy key creata per il collegamento HTTPS" || bad "deploy key creata"
grep -q '/home/\*/.config/ops-kb' /srv/ops/maint/templates/borgmatic-config.yaml && pass "modello di backup: cartella del token esclusa" || bad "esclusione del token dal backup"
bash "$PKG/bootstrap.sh" --admin tester > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'Knowledge Base disponibile' /tmp/out.txt && ! grep -q 'Vuoi collegare' /tmp/out.txt && pass "rieseguendo il bootstrap con KB collegata: solo sincronizzazione, nessuna domanda" || { bad "bootstrap ripetuto (rc=$rc)"; tail -5 /tmp/out.txt; }
rm -rf /srv/ops; mv /srv/ops.k8 /srv/ops; cp -p /tmp/ref.k8 /var/lib/ops-bootstrap/pacchetto.manifest; rm -f /tmp/ref.k8
runuser -u tester -- crontab -r 2>/dev/null || true
runuser -u tester -- rm -rf /home/tester/.config/ops-kb
t "foundation di prova ripristinata (repository pulito)" bash -c "[ -z \"\$(runuser -u tester -- git -C /srv/ops status --porcelain)\" ]"

kill $SRVPID 2>/dev/null; rm -rf $S /tmp/kbt /tmp/risposte /usr/local/share/ca-certificates/kb-test.crt; update-ca-certificates --fresh >/dev/null 2>&1
