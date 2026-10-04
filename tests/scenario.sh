#!/usr/bin/env bash
# scenario.sh — collaudo di bootstrap.sh dentro un container Ubuntu pulito (eseguito come root).
# Non richiede systemd: verifica distribuzione, idempotenza, conflitti, adattatori, componenti inattivi.
set -u
export DEBIAN_FRONTEND=noninteractive
PKG=/pkg; FAILS=0; N=0
pass() { N=$((N+1)); echo "PASS $*"; }
bad()  { N=$((N+1)); FAILS=$((FAILS+1)); echo "FAIL $*"; }
t()    { local d=$1; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else bad "$d"; fi; }
tn()   { local d=$1; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else pass "$d"; fi; }
KBARGS=(--kb-remote /kbremote.git --kb-id testsrv)
run()  { bash "$PKG/bootstrap.sh" "$@" "${KBARGS[@]}" > /tmp/out.txt 2>&1; echo $?; }
asu()  { runuser -u tester -- bash -c "cd ~ && $1"; }

echo "== preparazione: repository remoto FITTIZIO della Knowledge Base"
apt-get install -y -qq git >/dev/null 2>&1
mkdir -p /tmp/kbsrc/records && cd /tmp/kbsrc && git init -q -b main && printf '# Indice (fittizio)\n\nKnowledge Base di prova.\n' > INDEX.md \
  && printf '# Record\n\nFormato di prova.\n' > records/README.md && printf '.kb-index.md\n' > .gitignore \
  && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm "KB fittizia" && cd / \
  && git clone -q --bare /tmp/kbsrc /kbremote.git && chmod -R a+rwX /kbremote.git && git config --system --add safe.directory '*'
echo "== preparazione: utente amministratore"
useradd -m -s /bin/bash -G sudo -c "Tester Uno,,," tester

echo "== T1 protezione: /srv/ops preesistente non del pacchetto"
mkdir -p /srv/ops; rc=$(run --admin tester --check)
[ "$rc" = 3 ] && grep -q 'non è stato creato da questo pacchetto' /tmp/out.txt && pass "si ferma su /srv/ops estranea" || { bad "protezione /srv/ops (rc=$rc)"; cat /tmp/out.txt; }
rmdir /srv/ops
mkdir -p /usr/local/sbin; touch /usr/local/sbin/servern100-maint; rc=$(run --admin tester --check)
[ "$rc" = 3 ] && pass "si ferma sul server di origine" || bad "protezione servern100 (rc=$rc)"
rm /usr/local/sbin/servern100-maint

echo "== T2 --check senza modifiche"
rc=$(run --admin tester --check)
[ "$rc" = 0 ] && [ ! -e /srv/ops ] && [ ! -e /var/log/ops-bootstrap.log ] && pass "--check non modifica nulla" || { bad "--check (rc=$rc)"; cat /tmp/out.txt; }
tn "argomento mancante rifiutato" bash "$PKG/bootstrap.sh" --admin root --check

rc=$(run --admin tester --knowledge-base-only --check)
[ "$rc" = 3 ] && grep -q 'richiede una /srv/ops già preparata' /tmp/out.txt && pass "--knowledge-base-only rifiutato su macchina non preparata" || bad "kb-only senza preparazione (rc=$rc)"

echo "== T3 prima esecuzione"
rc=$(run --admin tester); cp /tmp/out.txt /tmp/first.txt
[ "$rc" = 0 ] && pass "bootstrap completato" || { bad "bootstrap (rc=$rc)"; tail -30 /tmp/out.txt; }
t "Knowledge Base recuperata (repository separato)" test -d /srv/ops/knowledge-base/.git
t "kb status come amministratore" runuser -u tester -- /srv/ops/bin/kb status
tn "knowledge-base non versionata nella foundation" bash -c "runuser -u tester -- git -C /srv/ops ls-files | grep -q '^knowledge-base/'"
t "kb.conf con nome tecnico del server" grep -qx 'KB_SERVER_ID=testsrv' /srv/ops/kb.conf
t "deploy key del server creata" test -f ~tester/.ssh/kb_deploy.pub
t "cron assente segnalato (nessuna sincronizzazione periodica)" grep -q 'cron assente' /tmp/first.txt

echo "== T4 contenuto distribuito"
t "AGENTS.md con hostname" grep -q '^# testsrv — istruzioni' /srv/ops/AGENTS.md
t "AGENTS.md con proprietario" grep -q 'Autorizzazione permanente di Tester' /srv/ops/AGENTS.md
t "CLAUDE.md adattatore" grep -qx '@AGENTS.md' /srv/ops/CLAUDE.md
t "checklist presente" test -f /srv/ops/docs/bootstrap/configurazione-server-base.md
t "avanzamento IN CORSO" grep -qx 'STATO: IN CORSO' /srv/ops/docs/bootstrap/avanzamento.md
tn "nessun segnaposto rimasto fuori da maint/" bash -c "grep -rl '@@[A-Z_]*@@' /srv/ops --exclude-dir=maint --exclude-dir=.git"
tn "nessun servern100 in script, parametri e regole" bash -c "grep -l servern100 /srv/ops/bin/* /srv/ops/maint/ops-maint /srv/ops/maint/install-maint /srv/ops/host.conf /srv/ops/AGENTS.md /srv/ops/STATUS.md"
echo "   (menzioni di servern100 ammesse, come origine: $(grep -rl servern100 /srv/ops --exclude-dir=.git | sed 's|/srv/ops/||' | paste -sd' '))"
t "un solo commit, repository pulito" bash -c "[ \$(runuser -u tester -- git -C /srv/ops rev-list --count HEAD) = 1 ] && [ -z \"\$(runuser -u tester -- git -C /srv/ops status --porcelain)\" ]"
t "proprietario di /srv/ops" bash -c "[ \$(stat -c %U /srv/ops/AGENTS.md) = tester ]"
t "script eseguibili" test -x /srv/ops/bin/quick-check -a -x /srv/ops/maint/install-maint
t "node >= 22" bash -c "node --version | grep -qE '^v(2[2-9]|[3-9][0-9])\.'"
t "claude installato per tester" asu 'PATH=~/.npm-global/bin:$PATH claude --version'
t "funzione claude nelle shell interattive" bash -c "runuser -u tester -- bash -ic 'type -t claude' 2>/dev/null | grep -qx function"
t "~/CLAUDE.md solo rimando" bash -c "grep -qx '@/srv/ops/AGENTS.md' ~tester/CLAUDE.md && [ \$(wc -l < ~tester/CLAUDE.md) -le 6 ]"
t "impostazioni Claude" bash -c "jq -e '.env.DISABLE_AUTOUPDATER==\"1\" and .autoUpdatesChannel==\"stable\"' ~tester/.claude/settings.json"
t "script root installato" bash -c "[ \"\$(stat -c '%U %a' /usr/local/sbin/ops-maint)\" = 'root 755' ]"
t "parametri root" bash -c "grep -qx ADMIN=tester /etc/ops-maint.conf && [ \"\$(stat -c '%U %a' /etc/ops-maint.conf)\" = 'root 644' ]"
t "inbox root:tester 2770" bash -c "[ \"\$(stat -c '%U %G %a' /var/lib/ops-maint/inbox)\" = 'root tester 2770' ]"
t "finestra non approvata" grep -qx APPROVED=no /var/lib/ops-maint/inbox/window.conf
tn "nessun timer o servizio ops abilitato" bash -c "ls /etc/systemd/system/*.wants/ 2>/dev/null | grep -q '^ops-'"
t "unit cli-update con utente" grep -qx User=tester /etc/systemd/system/ops-cli-update.service

echo "== T5 seconda esecuzione (idempotenza)"
rc=$(run --admin tester)
[ "$rc" = 0 ] && ! grep -qE '  (create|update): ' /tmp/out.txt && pass "seconda esecuzione senza modifiche" || { bad "idempotenza (rc=$rc)"; grep -E 'create|update|STOP' /tmp/out.txt; }
t "ancora un solo commit" bash -c "[ \$(runuser -u tester -- git -C /srv/ops rev-list --count HEAD) = 1 ]"
t "--check dopo l'installazione" bash "$PKG/bootstrap.sh" --admin tester --check

echo "== T6 conflitto su file gestito"
echo '# modifica locale' >> /srv/ops/bin/quick-check; rc=$(run --admin tester)
[ "$rc" = 3 ] && grep -q 'modificato rispetto al pacchetto' /tmp/out.txt && tail -1 /srv/ops/bin/quick-check | grep -q 'modifica locale' \
  && pass "si ferma senza sovrascrivere" || bad "conflitto (rc=$rc)"
runuser -u tester -- git -C /srv/ops checkout -q -- bin/quick-check

echo "== T7 file compilati dall'agente conservati"
echo '- nota locale' >> /srv/ops/STATUS.md; rc=$(run --admin tester)
[ "$rc" = 0 ] && tail -1 /srv/ops/STATUS.md | grep -q 'nota locale' && pass "STATUS.md conservato" || bad "seed (rc=$rc)"
runuser -u tester -- git -C /srv/ops checkout -q -- STATUS.md

echo "== T8 nuova versione del pacchetto"
rm -rf /tmp/pkg2; cp -a "$PKG" /tmp/pkg2; echo 'Riga aggiunta nella nuova versione.' >> /tmp/pkg2/payload/ops/docs/runbooks/controllo-rapido.md
bash /tmp/pkg2/bootstrap.sh --admin tester > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'update: docs/runbooks/controllo-rapido.md' /tmp/out.txt && pass "aggiorna solo i file non modificati localmente" || { bad "aggiornamento (rc=$rc)"; tail -5 /tmp/out.txt; }

echo "== T12 Knowledge Base condivisa"
t "regola SYNC BEFORE WORK" grep -q 'SYNC BEFORE WORK' /srv/ops/AGENTS.md
t "regola VERIFY BEFORE PUBLISH" grep -q 'VERIFY BEFORE PUBLISH' /srv/ops/AGENTS.md
t "regola APPEND ONLY" grep -q 'APPEND ONLY' /srv/ops/AGENTS.md
t "regole KNOWLEDGE FIRST e LEARN & CONSOLIDATE" bash -c "grep -q 'KNOWLEDGE FIRST' /srv/ops/AGENTS.md && grep -q 'LEARN & CONSOLIDATE' /srv/ops/AGENTS.md"
H=$(git -C /srv/ops/knowledge-base rev-parse HEAD)
runuser -u tester -- /srv/ops/bin/kb sync --quiet; runuser -u tester -- /srv/ops/bin/kb sync --quiet
[ "$(git -C /srv/ops/knowledge-base rev-parse HEAD)" = "$H" ] && pass "sincronizzazione ripetuta senza modifiche" || bad "sync ripetuto"
echo "-- scenario completo dello strumento kb (due copie, dati fittizi)"
runuser -u tester -- bash "$PKG/tests/kb-scenario.sh" /srv/ops/bin/kb /kbremote.git > /tmp/kbs.txt 2>&1; rc=$?
grep -E '^(FAIL|== RISULTATO)' /tmp/kbs.txt | sed 's/^/   /'
[ "$rc" = 0 ] && pass "scenario kb: $(grep -o '[0-9]*/[0-9]* superati' /tmp/kbs.txt)" || bad "scenario kb"
echo "-- remoto irraggiungibile: fase dichiarata NON completata"
mv /srv/ops/knowledge-base /tmp/kb-salvata; cp -p /srv/ops/kb.conf /tmp/kb.conf.salvato
sed -i 's|^KB_REMOTE=.*|KB_REMOTE=ssh://git@192.0.2.1/inesistente.git|' /srv/ops/kb.conf
bash "$PKG/bootstrap.sh" --admin tester --knowledge-base-only > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 4 ] && grep -q 'NON RECUPERATA' /tmp/out.txt && pass "senza accesso: esito 4 e messaggio esplicito" || { bad "remoto irraggiungibile (rc=$rc)"; tail -5 /tmp/out.txt; }
t "istruzioni con la chiave pubblica del server" grep -q 'ssh-ed25519' /tmp/out.txt
tn "nessun passo operativo in --knowledge-base-only" grep -qE '== (1|3|4|5)/5' /tmp/out.txt
cp -p /tmp/kb.conf.salvato /srv/ops/kb.conf; mv /tmp/kb-salvata /srv/ops/knowledge-base
echo "-- migrazione da una copia incorporata 0.2.0"
mv /srv/ops/knowledge-base /tmp/kb-salvata; mkdir -p /srv/ops/knowledge-base; echo "pagina locale 0.2.0" > /srv/ops/knowledge-base/pagina.md; chown -R tester: /srv/ops/knowledge-base
bash "$PKG/bootstrap.sh" --admin tester --knowledge-base-only > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && pass "kb-only su copia 0.2.0: completato" || { bad "migrazione 0.2.0 (rc=$rc)"; tail -5 /tmp/out.txt; }
t "copia 0.2.0 conservata" bash -c "grep -q 'pagina locale 0.2.0' /srv/ops/knowledge-base.v0.2.0-*/pagina.md"
t "nuova copia dal repository condiviso" test -d /srv/ops/knowledge-base/.git
t "foundation pulita dopo la migrazione" bash -c "[ -z \"\$(runuser -u tester -- git -C /srv/ops status --porcelain)\" ]"
rm -rf /srv/ops/knowledge-base.v0.2.0-* /tmp/kb-salvata

echo "== T9 conflitti nella home e nei parametri"
useradd -m -s /bin/bash -G sudo tester2; echo 'alias claude=true' >> ~tester2/.bash_aliases
rc=$(run --admin tester2 --check)
[ "$rc" = 3 ] && grep -q 'definisce già claude' /tmp/out.txt && grep -q 'ops-maint.conf indica ADMIN=tester' /tmp/out.txt \
  && pass "conflitti nella home e ADMIN diverso rilevati" || { bad "conflitti home (rc=$rc)"; cat /tmp/out.txt; }

echo "== T10 script sulla macchina"
out=$(asu '/srv/ops/bin/quick-check'); echo "$out" | sed 's/^/   | /'
echo "$out" | grep -q 'Configurazione iniziale' && echo "$out" | grep -q 'backup non ancora configurato' && pass "quick-check riconosce la configurazione incompleta" || bad "quick-check"
asu '/srv/ops/bin/quick-check --gate' | grep -q 'Configurazione iniziale' && bad "gate non deve contare l'avanzamento" || pass "gate indipendente dall'avanzamento"
t "origini della finestra (release della macchina)" bash -c ". /etc/os-release; /usr/local/sbin/ops-maint origins | grep -qF \"Ubuntu:\${VERSION_ID//./\\\\.}/\$VERSION_CODENAME\""
out=$(DRY_RUN=1 /usr/local/sbin/ops-maint window 2>&1); echo "$out" | sed 's/^/   | /'
echo "$out" | grep -q 'niente da fare' && pass "finestra DRY_RUN senza azioni" || bad "finestra DRY_RUN"
t "ops-maint procs" /usr/local/sbin/ops-maint procs
tn "enable window rifiutato senza systemd/prerequisiti" /srv/ops/maint/install-maint enable window
t "maint-approve --show" asu '/srv/ops/bin/maint-approve --show'
t "heartbeat senza configurazione esce pulito" asu '/srv/ops/bin/heartbeat'
t "install-maint rieseguibile" /srv/ops/maint/install-maint install --admin tester
out=$(asu 'timeout 120 /srv/ops/bin/cli-update --verify' 2>&1); rc=$?
[ "$rc" != 0 ] && pass "cli-update --verify fallisce senza login (prerequisito del timer): $(echo "$out" | tail -1 | cut -c1-90)" || bad "cli-update --verify inatteso"

echo "== T13 correzioni 0.4.0 di bootstrap.sh (A1 systemctl senza corrispondenze, A2 kb status)"
# systemctl simulato come su Ubuntu 26.04: con un filtro senza corrispondenze esce con 1; senza filtri elenca le unit
mkdir -p /run/systemd/system /tmp/fakesd
cat > /tmp/fakesd/systemctl <<'EOF'
#!/bin/bash
if [ "$1" = list-unit-files ]; then
  shift; for a; do case $a in --*) ;; *) exit 1 ;; esac; done
  [ -e /tmp/systemctl-fail ] && exit 4
  printf 'ops-postboot.service disabled enabled\nssh.service enabled enabled\n'; exit 0
fi
exit 0
EOF
printf "#!/bin/sh\nexit 0\n" > /tmp/fakesd/systemd-tmpfiles
chmod +x /tmp/fakesd/systemctl /tmp/fakesd/systemd-tmpfiles
SAVEPATH=$PATH; export PATH=/tmp/fakesd:$PATH
bash -c 'set -euo pipefail; en=$(systemctl list-unit-files "ops-*" --state=enabled --no-legend 2>/dev/null | awk "{print \$1}" | paste -sd" "); echo "$en"' >/dev/null 2>&1 \
  && bad "A1: il systemctl simulato non riproduce il difetto della 0.3.0" || pass "A1: difetto della 0.3.0 riprodotto (codice di uscita 1 con pipefail)"
rc=$(run --admin tester)
[ "$rc" = 0 ] && grep -q 'nessuna unit ops-\* abilitata' /tmp/out.txt && pass "A1: bootstrap esce con 0 senza unit ops-* abilitate" || { bad "A1 (rc=$rc)"; tail -5 /tmp/out.txt; }
touch /tmp/systemctl-fail; rc=$(run --admin tester)
[ "$rc" = 3 ] && grep -q 'systemctl list-unit-files non riuscito (rc=4)' /tmp/out.txt && pass "A1: errore reale di systemctl segnalato (esito 3)" || { bad "A1 errore reale (rc=$rc)"; tail -5 /tmp/out.txt; }
rm -f /tmp/systemctl-fail; export PATH=$SAVEPATH; rm -rf /tmp/fakesd; rmdir /run/systemd/system 2>/dev/null || true
# kb status simulato nel pacchetto (output lunghissimo o errore): bootstrap aggiorna bin/kb, non modificato localmente
rm -rf /tmp/pkg3; cp -a "$PKG" /tmp/pkg3
sed -i '2i if [ "${1:-}" = status ] && [ -f /tmp/kb-status-mode ]; then case $(cat /tmp/kb-status-mode) in long) seq 1 200000 | sed "s/^/riga /"; exit 0 ;; fail) echo errore >\&2; exit 7 ;; esac; fi' /tmp/pkg3/payload/ops/bin/kb
echo long > /tmp/kb-status-mode
bash /tmp/pkg3/bootstrap.sh --admin tester "${KBARGS[@]}" > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'Knowledge Base disponibile: riga 1$' /tmp/out.txt && ! grep -qi 'broken pipe' /tmp/out.txt \
  && pass "A2: kb status di 200000 righe, prima riga e nessun Broken pipe" || { bad "A2 output lungo (rc=$rc)"; grep -iE 'knowledge|pipe' /tmp/out.txt | tail -5; }
echo fail > /tmp/kb-status-mode
bash /tmp/pkg3/bootstrap.sh --admin tester "${KBARGS[@]}" > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 4 ] && grep -q 'kb status non riuscito (rc=7)' /tmp/out.txt && pass "A2: kb status fallito → fase KB non completata (esito 4)" || { bad "A2 errore (rc=$rc)"; tail -5 /tmp/out.txt; }
rm -f /tmp/kb-status-mode; rc=$(run --admin tester)
[ "$rc" = 0 ] && grep -q 'update: bin/kb' /tmp/out.txt && pass "bin/kb del pacchetto ripristinato" || { bad "ripristino bin/kb (rc=$rc)"; tail -5 /tmp/out.txt; }
rm -rf /tmp/pkg3

echo "== T14 quick-check 0.4.0 (A3 Docker senza gruppo docker, A4 log ruotato)"
Q=/tmp/qc; rm -rf $Q; mkdir -p $Q/fakebin; cp /srv/ops/host.conf $Q/host.conf
TS=$(date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%S.000000)
sed -i "s|^BORG_REPO=.*|BORG_REPO=/x/repo|; s|^BORG_LOG=.*|BORG_LOG=$Q/borgmatic.log|" $Q/host.conf
printf 'Creating archive at "/x/repo::testsrv-%s"\nSuccessfully ran configuration file /etc/borgmatic/config.yaml\n' "$TS" > $Q/arch.txt
chmod -R a+rX $Q
qc() { runuser -u tester -- env OPS_DIR=$Q PATH="$Q/fakebin:$PATH" /srv/ops/bin/quick-check 2>&1; }
cp $Q/arch.txt $Q/borgmatic.log; rm -f $Q/borgmatic.log.1
qc | grep -q 'OK .*archivio Borg testsrv-' && pass "A4: archivio nel log corrente" || { bad "A4 log corrente"; qc | grep -i borg; }
: > $Q/borgmatic.log; cp $Q/arch.txt $Q/borgmatic.log.1; chmod a+r $Q/borgmatic.log.1
qc | grep -q 'OK .*archivio Borg testsrv-' && pass "A4: dopo la rotazione l'archivio si legge dal log precedente" || { bad "A4 log ruotato"; qc | grep -i borg; }
rm -f $Q/borgmatic.log.1
qc | grep -q 'ERRORE .*nessun archivio Borg' && pass "A4: senza archivio in nessuno dei due log resta ERRORE" || { bad "A4 senza archivio"; qc | grep -i borg; }
printf 'Creating archive at "/x/repo::testsrv-%s"\nCRITICAL errore\n' "$TS" > $Q/borgmatic.log.1; chmod a+r $Q/borgmatic.log.1
qc | grep -q 'ERRORE .*borgmatic con errori' && pass "A4: errore nel log ruotato segnalato" || { bad "A4 errore nel log ruotato"; qc | grep -i borg; }
# Docker installato, socket di root non scrivibile dall'amministratore, servizio attivo
printf '#!/bin/sh\nexit 1\n' > $Q/fakebin/docker
printf '#!/bin/sh\n[ "$1 $2 $3" = "is-active --quiet docker" ] && exit 0\nexec /bin/false\n' > $Q/fakebin/systemctl
chmod 0755 $Q/fakebin/*
python3 -c 'import socket; s=socket.socket(socket.AF_UNIX); s.bind("/run/docker.sock")' 2>/dev/null || true
chown root:root /run/docker.sock; chmod 0660 /run/docker.sock
qc | grep -q 'OK .*Docker attivo; nessun container previsto' && pass "A3: senza gruppo docker e senza container previsti: OK" || { bad "A3 senza container"; qc | sed -n '/^Docker/,+2p'; }
sed -i 's|^CONTAINERS=.*|CONTAINERS="web"|' $Q/host.conf
qc | grep -q 'ERRORE .*Docker non raggiungibile' && pass "A3: con container previsti resta ERRORE" || { bad "A3 con container"; qc | sed -n '/^Docker/,+2p'; }
rm -f /run/docker.sock; rm -rf $Q

echo "== T15 modello logrotate-borgmatic (A5)"
apt-get install -y -qq logrotate >/dev/null 2>&1
L=/tmp/lr; rm -rf $L; mkdir -p $L; cp /srv/ops/maint/templates/logrotate-borgmatic $L/conf
t "logrotate -d sul modello senza errori" bash -c "logrotate -d -s $L/state $L/conf 2>&1 | grep -qiE '^error' && exit 1 || exit 0"
sed -i "s|/var/log/borgmatic.log|$L/borgmatic.log|; s|su root adm|su root root|" $L/conf
echo 'Creating archive at "/x::testsrv-2026-01-01T03:00:00.000000"' > $L/borgmatic.log
logrotate -f -s $L/state $L/conf
t "rotazione forzata: log precedente non compresso (delaycompress) e nuovo log vuoto 0644" bash -c "grep -q 'Creating archive' $L/borgmatic.log.1 && [ ! -s $L/borgmatic.log ] && [ \"\$(stat -c '%U:%G %a' $L/borgmatic.log)\" = 'root:root 644' ]"
rm -rf $L

echo "== T16 script dei passi (parametri da host.conf; solo le parti eseguibili senza systemd)"
D=/srv/ops/docs/bootstrap
for f in passo3-cartelle passo6-pacchetti passo7-impostazioni passo8-docker passo9-manutenzione passo10-backup passo10b-rotazione-verifica passo12-verifiche passi-comune; do
  t "distribuito: $f.sh" test -f $D/$f.sh
done
tn "nessun valore della VM di laboratorio negli script" bash -c "grep -lE 'Hyper|Default Switch|resolute|10\.0\.0\.0/8|source_directories_must_exist|\"ip\"' $D/passo*.sh"
# lettore di host.conf: virgolette, commenti, valori non validi
H=/tmp/hc; rm -rf $H; mkdir -p $H; cp /srv/ops/host.conf $H/
hcrun() { OPS_DIR=$H bash -c 'die() { echo "DIE: $*"; exit 1; }; . /srv/ops/docs/bootstrap/passi-comune.sh; load_host_conf; '"$1"; }
sed -i 's|^LAN_CIDR=.*|LAN_CIDR="192.168.7.0/24"   # commento|; s|^DATA_MOUNT=.*|DATA_MOUNT=/dati   # commento|' $H/host.conf
[ "$(hcrun 'echo "$HOST|$ADMIN|$LAN_CIDR|$DATA_MOUNT|$SERVICES"')" = "testsrv|tester|192.168.7.0/24|/dati|ssh cron" ] \
  && pass "host.conf letto senza eseguirlo (virgolette e commenti)" || bad "lettore di host.conf: $(hcrun 'echo "$HOST|$ADMIN|$LAN_CIDR|$DATA_MOUNT|$SERVICES"')"
sed -i 's|^LAN_CIDR=.*|LAN_CIDR="192.168.7.1/24"|' $H/host.conf
hcrun true | grep -q 'LAN_CIDR non valido' && pass "LAN_CIDR non di rete rifiutato" || bad "LAN_CIDR non valido accettato"
sed -i 's|^LAN_CIDR=.*|LAN_CIDR="$(touch /tmp/eseguito)"|' $H/host.conf
hcrun true >/dev/null; [ ! -e /tmp/eseguito ] && pass "host.conf mai eseguito (comando nel valore ignorato)" || bad "host.conf eseguito"
sed -i 's|^LAN_CIDR=.*|LAN_CIDR=""|; s|^HOST=.*|HOST=altro|' $H/host.conf
hcrun true | grep -q 'diverso dall.hostname' && pass "HOST diverso dall'hostname rifiutato" || bad "HOST diverso accettato"
rm -rf $H /tmp/eseguito
# parametri mancanti: gli script si fermano prima di qualunque modifica
bash $D/passo3-cartelle.sh --dry-run > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'DATA_MOUNT vuoto' /tmp/out.txt && pass "passo3 senza DATA_MOUNT: si ferma" || { bad "passo3 senza DATA_MOUNT (rc=$rc)"; cat /tmp/out.txt; }
bash $D/passo7-impostazioni.sh --dry-run > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'LAN_CIDR vuoto' /tmp/out.txt && pass "passo7 senza LAN_CIDR: si ferma (nessuna regola UFW predefinita)" || { bad "passo7 senza LAN_CIDR (rc=$rc)"; cat /tmp/out.txt; }
bash $D/passo12-verifiche.sh > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 1 ] && grep -qE '(LAN_CIDR|BORG_REPO) vuoto' /tmp/out.txt && pass "passo12 senza parametri: si ferma" || { bad "passo12 senza parametri (rc=$rc)"; cat /tmp/out.txt; }
# passo 3 su disco unico: dry-run, creazione, ripetizione, rollback; disco in fstab non montato
cp -p /srv/ops/host.conf /tmp/host.conf.salvato; cp -p /etc/fstab /tmp/fstab.salvato
mkdir -p /dati; sed -i 's|^DATA_MOUNT=.*|DATA_MOUNT="/dati"|' /srv/ops/host.conf
bash $D/passo3-cartelle.sh --dry-run > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'disco unico' /tmp/out.txt && [ ! -e /dati/dati ] && pass "passo3 --dry-run: nessuna scrittura" || { bad "passo3 dry-run (rc=$rc)"; cat /tmp/out.txt; }
bash $D/passo3-cartelle.sh > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(stat -c '%U %a' /dati/dati /dati/dati/backup /dati/dati/backup/database | paste -sd' ')" = "root 755 root 750 root 750" ] \
  && pass "passo3: cartelle create con proprietario e permessi attesi" || { bad "passo3 (rc=$rc)"; cat /tmp/out.txt; }
bash $D/passo3-cartelle.sh > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'nulla da creare' /tmp/out.txt && pass "passo3 ripetibile" || { bad "passo3 ripetizione (rc=$rc)"; cat /tmp/out.txt; }
echo "/dev/disk/by-uuid/00000000-0000 /dati btrfs defaults,nofail 0 0" >> /etc/fstab
bash $D/passo3-cartelle.sh --dry-run > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'in /etc/fstab ma non è montato' /tmp/out.txt && pass "passo3: disco dati in fstab non montato → si ferma" || { bad "passo3 fstab (rc=$rc)"; cat /tmp/out.txt; }
cp -p /tmp/fstab.salvato /etc/fstab
# passo 10: configurazione generata dal modello e validata da borgmatic reale (PRECHECK; senza systemd si ferma dopo)
if apt-get install -y -qq --no-install-recommends borgbackup borgmatic >/dev/null 2>&1; then
  bash $D/passo10-backup.sh --dry-run > /tmp/out.txt 2>&1
  grep -q 'ok  configurazione generata valida' /tmp/out.txt && pass "passo10: configurazione dal modello valida ($(borgmatic --version 2>/dev/null))" || { bad "passo10 configurazione"; cat /tmp/out.txt; }
  grep -q -- '- path: /dati/dati/backup/borg-repo-plain' /tmp/out.txt && pass "passo10: repository derivato da DATA_MOUNT" || bad "passo10 repository"
  grep -q 'source_directories_must_exist' /tmp/out.txt && bad "passo10: scelta della VM trasferita" || pass "passo10: nessuna scelta della VM nella configurazione"
  sed -i 's|^CONTAINERS=.*|CONTAINERS="web"|' /srv/ops/host.conf
  bash $D/passo10-backup.sh --dry-run > /tmp/out.txt 2>&1; rc=$?
  [ "$rc" = 1 ] && grep -q 'solo la base senza servizi' /tmp/out.txt && pass "passo10 con servizi in host.conf: si ferma" || { bad "passo10 con servizi (rc=$rc)"; cat /tmp/out.txt; }
else
  bad "installazione di borgbackup/borgmatic nel container non riuscita"
fi
# passo 9: REQUIRED_UNITS derivato da SERVICES, solo la riga di assegnazione; valori estranei fermano lo script
cp -p /etc/ops-maint.conf /tmp/ops-maint.conf.salvato
sed -i 's|^SERVICES=.*|SERVICES="ssh cron ufw fail2ban docker"|; s|^CONTAINERS=.*|CONTAINERS=""|' /srv/ops/host.conf
bash $D/passo9-manutenzione.sh --dry-run > /tmp/out.txt 2>&1
grep -q 'previsto (da SERVICES):  ssh.socket|ssh.service cron.service ufw.service fail2ban.service docker.service$' /tmp/out.txt \
  && pass "passo9: REQUIRED_UNITS previsto dalle unità di SERVICES" || { bad "passo9 previsto"; cat /tmp/out.txt; }
sed -i 's/^REQUIRED_UNITS=.*/REQUIRED_UNITS=ssh.socket|ssh.service estraneo.service/' /etc/ops-maint.conf
bash $D/passo9-manutenzione.sh --dry-run > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "contiene 'estraneo.service'" /tmp/out.txt && pass "passo9: unità non derivata da SERVICES → si ferma" || { bad "passo9 estraneo (rc=$rc)"; cat /tmp/out.txt; }
cp -p /tmp/ops-maint.conf.salvato /etc/ops-maint.conf
bash $D/passo3-cartelle.sh --rollback > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e /dati/dati ] && pass "passo3 --rollback: rimosse solo le cartelle create" || { bad "passo3 rollback (rc=$rc)"; cat /tmp/out.txt; }
cp -p /tmp/host.conf.salvato /srv/ops/host.conf; rmdir /dati; rm -f /var/lib/ops-bootstrap/passo*.manifest
t "host.conf ripristinato, repository pulito" bash -c "[ -z \"\$(runuser -u tester -- git -C /srv/ops status --porcelain)\" ]"

# comando unico ops-installa, passo 5, rilevazione, esclusioni e regressioni della consegna 0.4.0 (T17–T23)
. "$PKG/tests/installa-scenario.sh"

echo "== T11 analisi statica (shellcheck -S warning)"
apt-get install -y -qq shellcheck >/dev/null 2>&1
for f in "$PKG/bootstrap.sh" "$PKG"/payload/ops/bin/* "$PKG/payload/ops/maint/ops-maint" "$PKG/payload/ops/maint/install-maint" "$PKG"/payload/ops/docs/bootstrap/*.sh "$PKG/payload/ops/docs/bootstrap/ops-installa"; do
  if shellcheck -S warning -x -P SCRIPTDIR "$f" > /tmp/sc.txt 2>&1; then pass "shellcheck ${f#$PKG/}"; else bad "shellcheck ${f#$PKG/}"; sed 's/^/   | /' /tmp/sc.txt | head -30; fi
done

echo "== RISULTATO: $((N - FAILS))/$N superati"
[ "$FAILS" = 0 ]
