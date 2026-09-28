#!/usr/bin/env bash
# kb-scenario.sh KB_TOOL SORGENTE_KB — collaudo dello strumento kb con DATI FITTIZI: repository remoto temporaneo
# (bare, locale), due copie indipendenti "server-a" e "server-b". Nessun accesso a GitHub.
set -u
KB=$1; SRC=$2; T=$(mktemp -d); N=0; F=0
pass() { N=$((N+1)); echo "PASS $*"; }
bad()  { N=$((N+1)); F=$((F+1)); echo "FAIL $*"; }
t()    { local d=$1; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else bad "$d"; fi; }
tn()   { local d=$1; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else pass "$d"; fi; }
git clone -q --bare "$SRC" "$T/remote.git"
for s in a b; do printf 'KB_DIR=%s\nKB_REMOTE=%s\nKB_BRANCH=main\nKB_SERVER_ID=server-%s\n' "$T/$s" "$T/remote.git" "$s" > "$T/$s.conf"; done
A() { KB_CONF=$T/a.conf "$KB" "$@"; }; B() { KB_CONF=$T/b.conf "$KB" "$@"; }
fill() {  # $1 file RECORD.md, $2 stato: record fittizio completo
  sed -i -e "s/^stato: .*/stato: $2/" -e 's/^tecnologie: .*/tecnologie: esempio 1.0/' -e 's/^ambiente: .*/ambiente: container di prova (dati fittizi)/' "$1"
  for s in "Problema o obiettivo" "Prerequisiti" "Procedura" "Risultato osservato" "Test eseguiti" "Limitazioni"; do
    sed -i "s/^## $s\$/## $s\nContenuto fittizio di collaudo per la sezione $s./" "$1"; done
}
newrec() { "$@" new "Record fittizio di collaudo" | head -1; }

echo "== primo recupero e sincronizzazioni ripetute"
t "init server-a" A init; t "init server-b" B init
t "contenuto identico alla sorgente" bash -c "[ \"\$(git -C $T/a rev-parse 'HEAD^{tree}')\" = \"\$(git -C $T/remote.git rev-parse 'main^{tree}')\" ] && [ -z \"\$(git -C $T/a status --porcelain --untracked-files=no)\" ]"
H=$(git -C "$T/a" rev-parse HEAD); A sync --quiet; A sync --quiet
[ "$(git -C "$T/a" rev-parse HEAD)" = "$H" ] && [ -z "$(git -C "$T/a" status --porcelain --untracked-files=no)" ] && pass "sync ripetuto senza modifiche" || bad "sync ripetuto"
t "hook APPEND ONLY installato" test -x "$T/a/.git/hooks/pre-push"
echo "== nuovo record: validazione e pubblicazione"
R1=$(newrec A); ID1=$(basename "$(dirname "$R1")")
tn "bozza non valida (metadati con segnaposti)" A validate "$ID1"
fill "$R1" verificato; t "record completo valido" A validate "$ID1"
t "pubblicazione server-a" A publish "$ID1"
t "server-b recupera il record" bash -c "KB_CONF=$T/b.conf $KB sync --quiet && test -f $T/b/records/$ID1/RECORD.md"
t "indice generato con il record" grep -q "$ID1" "$T/b/.kb-index.md"
tn "indice non versionato" git -C "$T/b" ls-files --error-unmatch .kb-index.md
echo "== pubblicazioni concorrenti"
RA=$(newrec A); IA=$(basename "$(dirname "$RA")"); fill "$RA" parziale
RB=$(newrec B); IB=$(basename "$(dirname "$RB")"); fill "$RB" verificato
( A publish "$IA" > "$T/pa.txt" 2>&1; echo $? > "$T/pa.rc" ) & ( B publish "$IB" > "$T/pb.txt" 2>&1; echo $? > "$T/pb.rc" ) & wait
[ "$(cat "$T/pa.rc")" = 0 ] && [ "$(cat "$T/pb.rc")" = 0 ] && pass "entrambe le pubblicazioni riuscite" || { bad "pubblicazioni concorrenti"; cat "$T/pa.txt" "$T/pb.txt"; }
git -C "$T/remote.git" ls-tree -r --name-only main | grep -c "records/RECORD-" | grep -qx 3 && pass "remoto con 3 record, nessuno perso" || bad "record persi sul remoto"
grep -hq "avanzato" "$T/pa.txt" "$T/pb.txt" && pass "un push respinto e ritentato dopo il recupero" || echo "     (nessun respingimento in questa corsa: i push non si sono sovrapposti)"
t "server-a vede anche il record di server-b" bash -c "KB_CONF=$T/a.conf $KB sync --quiet && test -f $T/a/records/$IB/RECORD.md"
echo "== rifiuto di modifiche e cancellazioni"
echo "modifica" >> "$T/b/records/$ID1/RECORD.md"
tn "sync rifiuta con record modificato localmente" B sync --quiet
R2=$(newrec B); I2=$(basename "$(dirname "$R2")"); fill "$R2" verificato
tn "publish rifiuta con record modificato localmente" B publish "$I2"
git -C "$T/b" -c user.name=t -c user.email=t@t commit -qam "modifica di un record"
tn "push di una modifica respinto dall'hook" git -C "$T/b" push -q origin HEAD:main
git -C "$T/b" reset -q --hard origin/main
git -C "$T/b" -c user.name=t -c user.email=t@t rm -q -r "records/$ID1" && git -C "$T/b" -c user.name=t -c user.email=t@t commit -qm "cancellazione"
tn "push di una cancellazione respinto dall'hook" git -C "$T/b" push -q origin HEAD:main
git -C "$T/b" reset -q --hard origin/main
echo "p" >> "$T/b/INDEX.md"; git -C "$T/b" -c user.name=t -c user.email=t@t commit -qam "pagina"
tn "push di una modifica a una pagina consolidata respinto" git -C "$T/b" push -q origin HEAD:main
git -C "$T/b" reset -q --hard origin/main
t "record originale intatto sul remoto" bash -c "git -C $T/remote.git show main:records/$ID1/RECORD.md | grep -q '^id: $ID1'"
echo "== esclusione delle credenziali e dei dati riservati"
R3=$(newrec A); I3=$(basename "$(dirname "$R3")"); fill "$R3" verificato
K5="-----"; printf '%s\n' "${K5}BEGIN OPENSSH PRIVATE KEY${K5}" 'FITTIZIA' "${K5}END OPENSSH PRIVATE KEY${K5}" > "$(dirname "$R3")/chiave.txt"   # blocco fittizio costruito a runtime
tn "chiave privata rifiutata" A publish "$I3"; rm "$(dirname "$R3")/chiave.txt"
echo "token: ghp_$(head -c 30 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-36)" >> "$R3"; tn "token GitHub rifiutato" A validate "$I3"; sed -i '$d' "$R3"
echo "server interno 192.168.77.5" >> "$R3"; tn "indirizzo privato rifiutato" A validate "$I3"; sed -i '$d' "$R3"
echo "contatto mario.rossi@esempio.it" >> "$R3"; tn "indirizzo email rifiutato" A validate "$I3"; sed -i '$d' "$R3"
t "dopo la pulizia il record è valido" A validate "$I3"
echo "== correzione di un record precedente"
sed -i "s/^corregge:.*/corregge: $ID1/" "$R3"; t "record correttivo pubblicato" A publish "$I3"
A index >/dev/null; grep "$ID1" "$T/a/.kb-index.md" | grep -q "$I3" && pass "indice: record precedente segnato 'corretto da'" || bad "indice corretto-da"
echo "== assenza di rete"
sed -i "s|^KB_REMOTE=.*|KB_REMOTE=ssh://git@192.0.2.1/inesistente.git|" "$T/a.conf"; git -C "$T/a" remote set-url origin ssh://git@192.0.2.1/inesistente.git
out=$(KB_TIMEOUT=3 KB_CONF=$T/a.conf "$KB" sync 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q "copia locale" <<< "$out" && pass "offline: consultazione della copia locale dichiarata" || bad "offline (rc=$rc): $out"
t "offline: ricerca locale" bash -c "KB_CONF=$T/a.conf $KB search 'record' | grep -q ."
R4=$(newrec A); I4=$(basename "$(dirname "$R4")"); fill "$R4" verificato
tn "offline: pubblicazione rimandata, record conservato" bash -c "KB_TIMEOUT=3 KB_CONF=$T/a.conf $KB publish $I4"
t "offline: record locale ancora presente" test -f "$R4"
echo "== inizializzazione su cartella esistente non Git"
mkdir -p "$T/c"; echo x > "$T/c/pagina.md"; printf 'KB_DIR=%s\nKB_REMOTE=%s\nKB_SERVER_ID=server-c\n' "$T/c" "$T/remote.git" > "$T/c.conf"
tn "init rifiuta cartella esistente" env KB_CONF=$T/c.conf "$KB" init; t "cartella esistente intatta" grep -qx x "$T/c/pagina.md"
echo "== RISULTATO KB: $((N-F))/$N superati"
rm -rf "$T"; [ "$F" = 0 ]
