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
t "origini della finestra" bash -c "/usr/local/sbin/ops-maint origins | grep -q 'Ubuntu:24\\\\.04/noble'"
out=$(DRY_RUN=1 /usr/local/sbin/ops-maint window 2>&1); echo "$out" | sed 's/^/   | /'
echo "$out" | grep -q 'niente da fare' && pass "finestra DRY_RUN senza azioni" || bad "finestra DRY_RUN"
t "ops-maint procs" /usr/local/sbin/ops-maint procs
tn "enable window rifiutato senza systemd/prerequisiti" /srv/ops/maint/install-maint enable window
t "maint-approve --show" asu '/srv/ops/bin/maint-approve --show'
t "heartbeat senza configurazione esce pulito" asu '/srv/ops/bin/heartbeat'
t "install-maint rieseguibile" /srv/ops/maint/install-maint install --admin tester
out=$(asu 'timeout 120 /srv/ops/bin/cli-update --verify' 2>&1); rc=$?
[ "$rc" != 0 ] && pass "cli-update --verify fallisce senza login (prerequisito del timer): $(echo "$out" | tail -1 | cut -c1-90)" || bad "cli-update --verify inatteso"

echo "== T11 analisi statica (shellcheck -S warning)"
apt-get install -y -qq shellcheck >/dev/null 2>&1
for f in "$PKG/bootstrap.sh" "$PKG"/payload/ops/bin/* "$PKG/payload/ops/maint/ops-maint" "$PKG/payload/ops/maint/install-maint"; do
  if shellcheck -S warning -x "$f" > /tmp/sc.txt 2>&1; then pass "shellcheck ${f#$PKG/}"; else bad "shellcheck ${f#$PKG/}"; sed 's/^/   | /' /tmp/sc.txt | head -30; fi
done

echo "== RISULTATO: $((N - FAILS))/$N superati"
[ "$FAILS" = 0 ]
