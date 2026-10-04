#!/usr/bin/env bash
# installa-scenario.sh — collaudo di ops-installa (comando unico) e delle correzioni 0.5.0, dentro il container di
# scenario.sh, dopo bootstrap.sh (utente amministratore "tester"). Usa le funzioni pass/bad/t/tn di scenario.sh.
#
# Parte reale: installazione da parte di bootstrap.sh, impronte di root, --piano senza sudo, integrità, passo 5 su
# gruppi reali, rilevazione dei parametri, quick-check con le esclusioni, regressioni dei difetti della consegna.
# Flusso completo: in una radice di prova (OPS_INSTALLA_TEST_ROOT, ignorata dalla copia in /usr/local/sbin) con gli
# script dei passi sostituiti da simulazioni che registrano le chiamate: ordine, dry-run, arresto, ripresa, soste
# (SSH, riavvio, approvazione), avanzamento, log. Senza systemd i passi reali 6–12 restano da provare su VM.
D=/srv/ops/docs/bootstrap
RUNNER=$D/ops-installa

echo "== T17 ops-installa installato da bootstrap.sh"
t "ops-installa in /usr/local/sbin, root 0755" bash -c "[ \"\$(stat -c '%U %a' /usr/local/sbin/ops-installa)\" = 'root 755' ] && cmp -s /usr/local/sbin/ops-installa $RUNNER"
t "impronte di riferimento di root (cartella 0700, file 0644)" bash -c "[ \"\$(stat -c '%U %a' /var/lib/ops-bootstrap)\" = 'root 700' ] && [ \"\$(stat -c '%U %a' /var/lib/ops-bootstrap/pacchetto.manifest)\" = 'root 644' ]"
t "impronte di root = manifest distribuito" cmp -s /var/lib/ops-bootstrap/pacchetto.manifest /srv/ops/.bootstrap/manifest
t "nuovi file distribuiti (passo5, verifiche, rilevazione)" test -f $D/passo5-utenti.sh -a -f $D/verifiche-base.sh -a -f $D/rileva-parametri.sh
out=$(runuser -u tester -- /usr/local/sbin/ops-installa 2>&1); rc=$?
[ "$rc" = 2 ] && pass "senza sudo: rifiutato (esito 2)" || bad "senza sudo (rc=$rc): $out"
out=$(runuser -u tester -- /usr/local/sbin/ops-installa --piano 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q 'PROFILO vuoto' <<<"$out" && grep -q 'LAN_CIDR vuoto' <<<"$out" && grep -q 'DATA_MOUNT vuoto' <<<"$out" && grep -q 'OFFSITE vuoto' <<<"$out" \
  && pass "--piano senza sudo: tutti i parametri mancanti in una volta (esito 3)" || { bad "--piano (rc=$rc)"; echo "$out" | tail -12; }
# integrità: un file del pacchetto modificato dall'amministratore ferma tutto prima di iniziare
cp -p $D/passo3-cartelle.sh /tmp/p3.salvato
runuser -u tester -- sh -c "echo '# modificato' >> $D/passo3-cartelle.sh"
out=$(/usr/local/sbin/ops-installa 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q 'modificato: docs/bootstrap/passo3-cartelle.sh' <<<"$out" && [ ! -e /var/lib/ops-bootstrap/installa.state ] \
  && pass "integrità: script modificato → nessun passo eseguito (esito 3)" || { bad "integrità script (rc=$rc)"; echo "$out" | tail -5; }
# anche se l'amministratore aggiorna il proprio manifest, vale la copia di root
h=$(sha256sum $D/passo3-cartelle.sh | cut -d' ' -f1)
runuser -u tester -- sed -i "s|^[0-9a-f]*  docs/bootstrap/passo3-cartelle.sh\$|$h  docs/bootstrap/passo3-cartelle.sh|" /srv/ops/.bootstrap/manifest
out=$(/usr/local/sbin/ops-installa 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q 'modificato: docs/bootstrap/passo3-cartelle.sh' <<<"$out" \
  && pass "integrità: manifest dell'amministratore aggiornato non basta (vale la copia di root)" || { bad "integrità manifest (rc=$rc)"; echo "$out" | tail -5; }
cp -p /tmp/p3.salvato $D/passo3-cartelle.sh; runuser -u tester -- git -C /srv/ops checkout -q -- .bootstrap/manifest 2>/dev/null || cp -p /var/lib/ops-bootstrap/pacchetto.manifest /srv/ops/.bootstrap/manifest
chown tester:tester /srv/ops/.bootstrap/manifest
# la radice di prova è ignorata dalla copia installata
mkdir -p /tmp/finta; out=$(OPS_INSTALLA_TEST_ROOT=/tmp/finta /usr/local/sbin/ops-installa 2>&1); rc=$?
[ "$rc" = 3 ] && ! grep -q /tmp/finta <<<"$out" && [ -z "$(ls -A /tmp/finta)" ] && pass "OPS_INSTALLA_TEST_ROOT ignorata dalla copia in /usr/local/sbin" || { bad "radice di prova nella copia installata (rc=$rc)"; echo "$out" | tail -3; }
rm -rf /tmp/finta /var/log/ops-installa /var/lib/ops-bootstrap/installa.state

echo "== T18 correzioni della consegna (regressioni)"
# P1 difetto 5: ultima iterazione di un ciclo in $( … | … ) con codice ≠ 0 (systemd-timesyncd assente su 26.04)
mkdir -p /tmp/fsc; printf '#!/bin/sh\n[ "$3" = chrony ] && exit 0\nexit 4\n' > /tmp/fsc/systemctl; chmod +x /tmp/fsc/systemctl
PATH=/tmp/fsc:$PATH bash -c 'set -euo pipefail; x=$(for u in chrony systemd-timesyncd; do systemctl is-active --quiet "$u" && echo "$u"; done | paste -sd" "); echo "$x"' >/dev/null 2>&1 \
  && bad "difetto 5 non riprodotto con la riga 0.4.0" || pass "difetto 5 riprodotto con la riga 0.4.0 (uscita ≠ 0)"
line=$(grep -m1 '^ntpc=' $D/passo7-impostazioni.sh)
out=$(PATH=/tmp/fsc:$PATH bash -c "set -euo pipefail; $line; echo \"[\$ntpc]\"" 2>&1)
[ "$out" = "[chrony]" ] && pass "difetto 5 corretto: riga di passo7 con chrony attivo e timesyncd assente → [chrony]" || bad "difetto 5: $out"
rm -rf /tmp/fsc
# prova generale suggerita: nessun "cmd && …" come ultima istruzione di un ciclo dentro $( … | … )
hits=$(grep -nE '\$\(\s*(for|while) [^)]*&& [^;)]*; *done *\|' $D/*.sh $RUNNER /srv/ops/bin/* /srv/ops/maint/ops-maint /srv/ops/maint/install-maint 2>/dev/null || true)
[ -z "$hits" ] && pass "nessun ciclo con '&&' finale in sostituzione di comando con pipe" || { bad "cicli a rischio:"; echo "$hits"; }
# P2 difetto 7: politiche UFW con e senza Docker
re=$(grep -oE "grep -qE 'Default: [^']*'" $D/passo12-verifiche.sh | sed -E "s/^grep -qE '//; s/'\$//")
grep -qE "$re" <<<'Default: deny (incoming), allow (outgoing), disabled (routed)' && grep -qE "$re" <<<'Default: deny (incoming), allow (outgoing), deny (routed)' \
  && ! grep -qE "$re" <<<'Default: deny (incoming), allow (outgoing), allow (routed)' \
  && pass "difetto 7: 12.5 accetta 'disabled (routed)' (senza Docker) e 'deny (routed)', rifiuta 'allow'" || bad "difetto 7: regex $re"
# P3: who, ora del ripristino, head sotto pipefail
tn "difetto 4: nessun 'who' nel passo 6" grep -qE '^\s*who\b' $D/passo6-pacchetti.sh
t "difetto 4: sessioni SSH lette con ss" grep -q "ss -tnH state established '( sport = :22 )'" $D/passo6-pacchetti.sh
tn "difetto 8: niente NextElapseUSecRealtime" grep -q NextElapseUSecRealtime $D/passo7-impostazioni.sh
t "difetto 8: ora limite calcolata all'armamento" grep -q 'RB_AT=$(date -d' $D/passo7-impostazioni.sh
tn "difetto 6: nessun '| head' nel passo 7" grep -qE '\| *head' $D/passo7-impostazioni.sh

echo "== T19 passo 5 su gruppi reali (lxd, docker, adm)"
# nel container esistono altri utenti con shell (ubuntu dell'immagine, tester2 dello scenario): disattivati per la prova
ALTRI=$(getent passwd | awk -F: '$7 !~ /(nologin|false|sync)$/ && $1 != "root" && $1 != "tester" {print $1}')
for u in $ALTRI; do usermod -s /usr/sbin/nologin "$u"; done
mkdir -p /etc/sudoers.d
groupadd -f lxd; groupadd -f docker; usermod -aG lxd,docker tester; gpasswd -d tester adm >/dev/null 2>&1 || true
cp -p /etc/group /tmp/group.salvato
bash $D/passo5-utenti.sh --dry-run > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'previsto: togliere tester da lxd' /tmp/out.txt && grep -q 'previsto: aggiungere tester a adm' /tmp/out.txt && cmp -s /etc/group /tmp/group.salvato \
  && pass "passo5 --dry-run: piano (adm, docker, lxd) senza modifiche" || { bad "passo5 dry-run (rc=$rc)"; cat /tmp/out.txt; }
grep -q 'sync con /bin/sync atteso' /tmp/out.txt && pass "difetto 1: l'utente sync (/bin/sync) non viola il controllo delle shell" || bad "difetto 1: sync"
bash $D/passo5-utenti.sh > /tmp/out.txt 2>&1; rc=$?
g=" $(id -nG tester) "
[ "$rc" = 0 ] && [[ "$g" == *" adm "* ]] && [[ "$g" != *" lxd "* ]] && [[ "$g" != *" docker "* ]] && [ -f "/etc/group.bak-$(date -u +%F)" ] \
  && pass "passo5: tester in adm, fuori da lxd e docker, copia di /etc/group" || { bad "passo5 (rc=$rc)"; cat /tmp/out.txt; }
bash $D/passo5-utenti.sh > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q 'gruppi già conformi' /tmp/out.txt && pass "passo5 ripetibile" || { bad "passo5 ripetizione (rc=$rc)"; cat /tmp/out.txt; }
bash $D/passo5-utenti.sh --rollback > /tmp/out.txt 2>&1; g=" $(id -nG tester) "
[[ "$g" == *" lxd "* ]] && [[ "$g" == *" docker "* ]] && [[ "$g" != *" adm "* ]] && pass "passo5 --rollback: gruppi di prima" || { bad "passo5 rollback"; cat /tmp/out.txt; }
echo 'tester ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/prova; chmod 0440 /etc/sudoers.d/prova
bash $D/passo5-utenti.sh > /tmp/out.txt 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'NOPASSWD presente' /tmp/out.txt && [[ " $(id -nG tester) " == *" lxd "* ]] && pass "passo5: NOPASSWD → si ferma senza modifiche" || { bad "passo5 NOPASSWD (rc=$rc)"; cat /tmp/out.txt; }
rm -f /etc/sudoers.d/prova; gpasswd -d tester lxd >/dev/null; gpasswd -d tester docker >/dev/null
rm -f /etc/group.bak-* /etc/gshadow.bak-* /var/lib/ops-bootstrap/passo5-utenti.manifest
for u in $ALTRI; do usermod -s /bin/bash "$u"; done

echo "== T20 rilevazione dei parametri (amministratore, senza sudo)"
apt-get install -y -qq iproute2 >/dev/null 2>&1
out=$(runuser -u tester -- bash $D/rileva-parametri.sh 2>&1); rc=$?
want=$(python3 -c 'import ipaddress,sys; print(ipaddress.ip_interface(sys.argv[1]).network)' "$(ip -o -4 addr show dev "$(ip -4 route show default | awk '{print $5; exit}')" | awk 'NR==1{print $4}')")
[ "$rc" = 0 ] && grep -q "LAN_CIDR    proposto: \"$want\"" <<<"$out" && grep -q 'PROFILO: base' <<<"$out" \
  && pass "rilevazione: LAN_CIDR $want proposto, profilo da chiedere" || { bad "rilevazione (rc=$rc)"; echo "$out"; }
cp -p /srv/ops/host.conf /tmp/hc.salvato
runuser -u tester -- bash $D/rileva-parametri.sh --scrivi --profilo base --esclusioni "2 7.1 10.3 11.2" > /tmp/out.txt 2>&1
[ "$(grep -E '^(LAN_CIDR|PROFILO|ESCLUSIONI|SERVICES)=' /srv/ops/host.conf | cut -d'#' -f1 | tr -s ' ' | paste -sd'|')" = "LAN_CIDR=\"$want\" |SERVICES=\"ssh cron ufw fail2ban\" |PROFILO=\"base\" |ESCLUSIONI=\"2 7.1 10.3 11.2\" " ] \
  && pass "--scrivi: chiavi vuote compilate, profilo ed esclusioni dichiarati" || { bad "--scrivi"; grep -E '^(LAN_CIDR|PROFILO|ESCLUSIONI|SERVICES)=' /srv/ops/host.conf; }
runuser -u tester -- sed -i 's|^LAN_CIDR=.*|LAN_CIDR="10.9.0.0/16"|' /srv/ops/host.conf
runuser -u tester -- bash $D/rileva-parametri.sh --scrivi >/dev/null 2>&1
grep -q '^LAN_CIDR="10.9.0.0/16"' /srv/ops/host.conf && pass "--scrivi non sovrascrive un valore compilato" || bad "--scrivi ha sovrascritto LAN_CIDR"
tn "--esclusioni con un valore non ammesso rifiutato" runuser -u tester -- bash $D/rileva-parametri.sh --esclusioni "6"
cp -p /tmp/hc.salvato /srv/ops/host.conf

echo "== T21 quick-check con le esclusioni dichiarate"
Q=/tmp/qe; rm -rf $Q; mkdir -p $Q; cp /srv/ops/host.conf $Q/host.conf
TS=$(date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%S.000000)
sed -i "s|^BORG_REPO=.*|BORG_REPO=/x/repo|; s|^BORG_LOG=.*|BORG_LOG=$Q/borgmatic.log|; s|^SERVICES=.*|SERVICES=\"\"|; s|^MOUNTS=.*|MOUNTS=\"/\"|" $Q/host.conf
printf 'Creating archive at "/x/repo::testsrv-%s"\nSuccessfully ran configuration file /etc/borgmatic/config.yaml\n' "$TS" > $Q/borgmatic.log; chmod -R a+rX $Q
qg() { runuser -u tester -- env OPS_DIR=$Q /srv/ops/bin/quick-check --gate 2>&1; }
qg | grep -q 'ATTENZIONE copia remota non configurata' && pass "senza esclusione: copia remota mancante = ATTENZIONE" || { bad "gate senza esclusione"; qg; }
sed -i 's|^ESCLUSIONI=.*|ESCLUSIONI="10.3 11.2"|' $Q/host.conf
out=$(qg); rc=$?
grep -q 'ESCLUSO    copia remota (10.3' <<<"$out" && ! grep -q 'ATTENZIONE copia remota' <<<"$out" \
  && pass "con 10.3 in ESCLUSIONI: riga ESCLUSO, non contata (gate: esito $rc)" || { bad "gate con esclusione"; echo "$out"; }
out=$(runuser -u tester -- env OPS_DIR=$Q /srv/ops/bin/quick-check 2>&1)
grep -q 'ESCLUSO    monitoraggio esterno (11.2' <<<"$out" && ! grep -q 'ATTENZIONE monitoraggio esterno' <<<"$out" \
  && pass "con 11.2 in ESCLUSIONI: monitoraggio esterno ESCLUSO" || { bad "11.2 escluso"; echo "$out" | grep -i monitor; }
rm -rf $Q

echo "== T22 flusso unico e ripresa (radice di prova, passi simulati)"
IT=/tmp/it; rm -rf $IT; mkdir -p $IT/srv $IT/fakebin $IT/rc $IT/var/lib/ops-maint/inbox $IT/var/run /tmp/it-dati
cp -a /srv/ops $IT/srv/ops
STUB='#!/bin/bash
n=$(basename "$0"); IT=$OPS_INSTALLA_TEST_ROOT
echo "$n${*:+ $*}" >> "$IT/calls"
f="$IT/rc/$n${1:+_${1#--}}"; rc=0; [ -f "$f" ] && rc=$(cat "$f")
case "$n ${1:-}" in
  "passo7-impostazioni.sh ") [ "$rc" = 0 ] && touch "$IT/timer-active" "$IT/ufw-active"
                             [ -e "$IT/nuovo-login" ] && echo "0 0 10.0.0.2:22 10.0.0.9:50999" >> "$IT/ss.txt" ;;
  "passo7-impostazioni.sh --confirm") rm -f "$IT/timer-active" ;;
esac
echo "simulazione di $n ${1:-}: uscita $rc"
exit "$rc"'
for s in passo3-cartelle passo5-utenti passo6-pacchetti passo7-impostazioni passo8-docker passo9-manutenzione passo10-backup passo10b-rotazione-verifica passo12-verifiche verifiche-base; do
  printf '%s\n' "$STUB" > $IT/srv/ops/docs/bootstrap/$s.sh
done
printf '%s\n' "$STUB" > $IT/srv/ops/maint/install-maint
chown -R tester:tester $IT/srv/ops
printf '#!/bin/bash\nIT=$OPS_INSTALLA_TEST_ROOT\ncase "$*" in\n  "is-active --quiet ops-ufw-rollback.timer") [ -e "$IT/timer-active" ] ;;\n  reboot) echo "systemctl reboot" >> "$IT/calls" ;;\n  *) exit 0 ;;\nesac\n' > $IT/fakebin/systemctl
printf '#!/bin/bash\n[ -e "$OPS_INSTALLA_TEST_ROOT/ufw-active" ] && echo "Status: active" || echo "Status: inactive"\n' > $IT/fakebin/ufw
printf '#!/bin/bash\ncat "$OPS_INSTALLA_TEST_ROOT/ss.txt"\n' > $IT/fakebin/ss
chmod +x $IT/fakebin/*
echo "0 0 10.0.0.2:22 10.0.0.9:50000" > $IT/ss.txt
echo boot-1 > $IT/boot_id
printf 'APPROVED=no\n' > $IT/var/lib/ops-maint/inbox/window.conf; chown tester:tester $IT/var/lib/ops-maint/inbox/window.conf
chown root:tester $IT/var/lib/ops-maint/inbox; chmod 2770 $IT/var/lib/ops-maint/inbox
HC=$IT/srv/ops/host.conf
sed -i 's|^LAN_CIDR=.*|LAN_CIDR="10.0.0.0/24"|; s|^DATA_MOUNT=.*|DATA_MOUNT="/tmp/it-dati"|; s|^SERVICES=.*|SERVICES="ssh cron ufw fail2ban"|; s|^PROFILO=.*|PROFILO="base"|; s|^ESCLUSIONI=.*|ESCLUSIONI="2 7.1 10.3 11.2"|' $HC
runuser -u tester -- git -C $IT/srv/ops commit -qam "prova: parametri" >/dev/null
reref() {  # impronte di riferimento della radice di prova = file attuali (come dopo bootstrap.sh)
  install -d -m 0700 $IT/var/lib/ops-bootstrap
  ( cd $IT/srv/ops && while read -r _ rel; do echo "$(sha256sum "$rel" | cut -d' ' -f1)  $rel"; done < .bootstrap/manifest ) > $IT/m.tmp
  install -m 0644 $IT/m.tmp $IT/var/lib/ops-bootstrap/pacchetto.manifest; install -o tester -g tester -m 0644 $IT/m.tmp $IT/srv/ops/.bootstrap/manifest
  runuser -u tester -- git -C $IT/srv/ops commit -qam "prova: impronte" >/dev/null 2>&1 || true
}
reref
oi() { printf "$1" > $IT/tty; OPS_INSTALLA_TEST_ROOT=$IT bash $RUNNER "${@:2}" > $IT/out.txt 2>&1 < /dev/null; echo $?; }
calls() { cat $IT/calls 2>/dev/null | paste -sd'|'; }
row() { grep -E "^\| $1\. " $IT/srv/ops/docs/bootstrap/avanzamento.md | awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}'; }

# piano non confermato: nessun passo
rc=$(oi 'no\n')
[ "$rc" = 3 ] && [ ! -e $IT/calls ] && grep -q 'piano non confermato' $IT/out.txt && pass "piano non confermato: nessun passo (esito 3)" || { bad "piano non confermato (rc=$rc)"; tail -5 $IT/out.txt; }
# orario del backup notturno
rc=$(OPS_INSTALLA_TEST_HM=0330 oi 'SI\n')
[ "$rc" = 3 ] && [ ! -e $IT/calls ] && grep -q '03:00–04:10' $IT/out.txt && pass "03:00–04:10 UTC: si ferma prima di iniziare" || bad "orario (rc=$rc)"

# esecuzione 1: fino alla sosta del firewall, uscita con "dopo"
rc=$(oi 'SI\ndopo\n')
want="verifiche-base.sh inizio|passo3-cartelle.sh --dry-run|passo3-cartelle.sh|verifiche-base.sh repo|passo5-utenti.sh --dry-run|passo5-utenti.sh|passo6-pacchetti.sh --dry-run|passo6-pacchetti.sh|passo7-impostazioni.sh --dry-run|passo7-impostazioni.sh"
[ "$rc" = 5 ] && [ "$(calls)" = "$want" ] && pass "esecuzione 1: passi in ordine con dry-run, sosta al firewall (esito 5)" || { bad "esecuzione 1 (rc=$rc)"; calls; tail -15 $IT/out.txt; }
[ "$(row 2)" = escluso ] && [ "$(row 3)" = fatto ] && [ "$(row 6)" = fatto ] && [ "$(row 7)" = "in attesa" ] \
  && pass "avanzamento: 2 escluso, 3–6 fatto, 7 in attesa" || { bad "avanzamento 1"; grep '^| ' $IT/srv/ops/docs/bootstrap/avanzamento.md; }
t "avanzamento registrato con commit dall'amministratore" bash -c "runuser -u tester -- git -C $IT/srv/ops log -1 --format=%s | grep -q 'ops-installa: avanzamento'"
L=$IT/var/log/ops-installa
t "log leggibili dall'amministratore senza sudo" runuser -u tester -- cat $L/ultimo/riepilogo.log $L/stato
tn "log non modificabili dall'amministratore" runuser -u tester -- sh -c "echo x >> $L/stato"
t "un log per comando, con comando, output e codice reale" bash -c "f=\$(ls $L/ultimo/*-3.log); grep -q '^# comando: bash .*passo3-cartelle.sh' \$f && grep -q 'simulazione di passo3-cartelle.sh' \$f && grep -q 'codice di uscita: 0' \$f"
t "stato: 7 in attesa di conferma SSH" grep -qE '^7 attesa-ssh ' $L/stato

# esecuzione 2 (ripresa dal nuovo login): conferma SSH, passi 8–12, sosta del riavvio
: > $IT/calls; echo "0 0 10.0.0.2:22 10.0.0.9:50111" >> $IT/ss.txt
rc=$(oi 'RIAVVIA\n')
want="passo7-impostazioni.sh --confirm|passo9-manutenzione.sh --dry-run|passo9-manutenzione.sh|passo10-backup.sh --dry-run|passo10-backup.sh|passo10b-rotazione-verifica.sh|verifiche-base.sh gate|passo12-verifiche.sh|install-maint enable postboot|systemctl reboot"
[ "$rc" = 5 ] && [ "$(calls)" = "$want" ] && pass "ripresa: nessun passo ripetuto, conferma SSH dal nuovo login, 8/10.3/11.2 esclusi, riavvio (esito 5)" || { bad "esecuzione 2 (rc=$rc)"; calls; tail -15 $IT/out.txt; }
grep -q "^BORG_REPO=\"/tmp/it-dati/dati/backup/borg-repo-plain\"" $HC && runuser -u tester -- git -C $IT/srv/ops log --format=%s | grep -q 'BORG_REPO in host.conf' \
  && pass "BORG_REPO scritto in host.conf con commit" || bad "BORG_REPO"
[ "$(row 8)" = escluso ] && [ "$(row 10)" = fatto ] && [ "$(row 12)" = "in attesa" ] && pass "avanzamento: 8 escluso (profilo), 10 fatto, 12 in attesa" || { bad "avanzamento 2"; grep '^| ' $IT/srv/ops/docs/bootstrap/avanzamento.md; }

# esecuzione 3: riavvio non avvenuto (stesso avvio) e rimandato: nessuna verifica
: > $IT/calls; rc=$(oi '\n')
[ "$rc" = 5 ] && [ -z "$(calls)" ] && grep -q 'Riavvio rimandato' $IT/out.txt && pass "stesso avvio: riavvio richiesto di nuovo, nessuna verifica (esito 5)" || { bad "esecuzione 3 (rc=$rc)"; calls; }

# esecuzione 4: dopo il riavvio, controlli, approvazione della finestra, completamento
echo boot-2 > $IT/boot_id; : > $IT/calls
rc=$(oi 'APPROVO\n')
want="verifiche-base.sh dopo-riavvio|verifiche-base.sh monitoraggio|verifiche-base.sh agenti|install-maint enable window|install-maint enable cli-update"
[ "$rc" = 0 ] && [ "$(calls)" = "$want" ] && pass "dopo il riavvio: controlli, attivazione, completata (esito 0)" || { bad "esecuzione 4 (rc=$rc)"; calls; tail -15 $IT/out.txt; }
grep -qx 'APPROVED=yes' $IT/var/lib/ops-maint/inbox/window.conf && [ "$(stat -c %U $IT/var/lib/ops-maint/inbox/window.conf)" = tester ] \
  && pass "finestra approvata con conferma scritta (APPROVED=yes, file dell'amministratore)" || bad "approvazione"
grep -qx 'STATO: COMPLETATO' $IT/srv/ops/docs/bootstrap/avanzamento.md && [ "$(row 12)" = fatto ] && [ "$(row 11)" = fatto ] \
  && pass "avanzamento: STATO: COMPLETATO solo a passo 12 superato" || { bad "completamento"; cat $IT/srv/ops/docs/bootstrap/avanzamento.md; }
t "repository di prova pulito dopo i commit" bash -c "[ -z \"\$(runuser -u tester -- git -C $IT/srv/ops status --porcelain)\" ]"
: > $IT/calls; rc=$(oi '')
[ "$rc" = 0 ] && [ -z "$(calls)" ] && pass "rilancio a configurazione completata: nessuna modifica" || bad "rilancio finale (rc=$rc)"

echo "== T23 arresto sugli errori, ripresa, integrità, rollback, ripristino automatico del firewall"
fresh() { rm -rf $IT/var/lib/ops-bootstrap/installa.state $IT/var/log/ops-installa $IT/calls $IT/timer-active $IT/ufw-active $IT/rc/*; echo boot-1 > $IT/boot_id
          printf 'APPROVED=no\n' > $IT/var/lib/ops-maint/inbox/window.conf; chown tester:tester $IT/var/lib/ops-maint/inbox/window.conf; reref; }
fresh; echo 1 > $IT/rc/passo6-pacchetti.sh
rc=$(oi 'SI\n')
[ "$rc" = 1 ] && [ "$(calls)" = "verifiche-base.sh inizio|passo3-cartelle.sh --dry-run|passo3-cartelle.sh|verifiche-base.sh repo|passo5-utenti.sh --dry-run|passo5-utenti.sh|passo6-pacchetti.sh --dry-run|passo6-pacchetti.sh" ] \
  && grep -q 'PASSO 6 NON SUPERATO (codice 1)' $IT/out.txt && pass "errore al passo 6: arresto, passo 7 non eseguito (esito 1)" || { bad "arresto (rc=$rc)"; calls; }
grep -qE '^6 errore ' $IT/var/lib/ops-bootstrap/installa.state && [ "$(row 6)" = errore ] && pass "stato e avanzamento: 6 errore" || bad "stato dell'errore"
t "codice reale nel log del passo" bash -c "grep -q 'codice di uscita: 1' \$(ls $L/ultimo/*-6.log)"
rm -f $IT/rc/passo6-pacchetti.sh; : > $IT/calls
rc=$(oi 'dopo\n')
[ "$rc" = 5 ] && [ "$(calls)" = "passo6-pacchetti.sh --dry-run|passo6-pacchetti.sh|passo7-impostazioni.sh --dry-run|passo7-impostazioni.sh" ] \
  && pass "ripresa dal passo 6 senza ripetere 1–5" || { bad "ripresa dopo errore (rc=$rc)"; calls; }
# ripristino automatico del firewall scattato (nessuna conferma in tempo)
rm -f $IT/timer-active $IT/ufw-active; : > $IT/calls
rc=$(oi '')
[ "$rc" = 1 ] && grep -q 'ripristino automatico ha disattivato UFW' $IT/out.txt && grep -qE '^7 errore ' $IT/var/lib/ops-bootstrap/installa.state \
  && pass "ripristino automatico scattato: errore al passo 7 con le istruzioni" || { bad "ripristino scattato (rc=$rc)"; tail -5 $IT/out.txt; }
rc=$(oi 'SI\n' --rollback 7)
[ "$rc" = 0 ] && grep -q 'passo7-impostazioni.sh --rollback' $IT/calls && grep -qE '^7 annullato ' $IT/var/lib/ops-bootstrap/installa.state \
  && pass "--rollback 7: script con --rollback, passo da rifare" || { bad "rollback (rc=$rc)"; tail -5 $IT/out.txt; }
# dry-run non superato: l'esecuzione reale non parte
fresh; echo 1 > $IT/rc/passo3-cartelle.sh_dry-run
rc=$(oi 'SI\n')
[ "$rc" = 1 ] && [ "$(calls)" = "verifiche-base.sh inizio|passo3-cartelle.sh --dry-run" ] && pass "dry-run non superato: esecuzione reale non avviata" || { bad "dry-run (rc=$rc)"; calls; }
# integrità nella radice di prova e correzione dichiarata
fresh; runuser -u tester -- sh -c "echo '# correzione locale' >> $IT/srv/ops/docs/bootstrap/passo9-manutenzione.sh"
rc=$(oi 'SI\n')
[ "$rc" = 3 ] && [ ! -e $IT/calls ] && pass "file modificato: nessun passo eseguito" || { bad "integrità radice di prova (rc=$rc)"; calls; }
rc=$(oi 'SI\n' --dichiara-correzione docs/bootstrap/passo9-manutenzione.sh)
[ "$rc" = 0 ] && grep -q '  docs/bootstrap/passo9-manutenzione.sh  ' $IT/etc/ops-installa/correzioni && [ "$(stat -c '%U %a' $IT/etc/ops-installa/correzioni)" = "root 644" ] \
  && pass "correzione dichiarata con conferma scritta (impronta in un file di root)" || { bad "dichiarazione (rc=$rc)"; tail -5 $IT/out.txt; }
rc=$(oi 'SI\ndopo\n')
[ "$rc" = 5 ] && grep -q 'correzioni locali dichiarate in .*passo9-manutenzione.sh' $IT/out.txt \
  && pass "con la correzione dichiarata l'esecuzione procede (fino alla sosta del firewall)" || { bad "dopo la dichiarazione (rc=$rc)"; tail -5 $IT/out.txt; }
# conferma del firewall nella STESSA esecuzione: il nuovo login compare mentre ops-installa attende
fresh; echo "0 0 10.0.0.2:22 10.0.0.9:50000" > $IT/ss.txt; touch $IT/nuovo-login
rc=$(oi 'SI\n\n')
grep -q 'passo7-impostazioni.sh --confirm' $IT/calls && grep -q 'nuovo login SSH dalla LAN rilevato: 10.0.0.2:22>10.0.0.9:50999' $IT/out.txt \
  && grep -qE '^7 fatto ' $IT/var/lib/ops-bootstrap/installa.state && [ "$rc" = 5 ] && grep -q 'Riavvio rimandato' $IT/out.txt \
  && pass "conferma SSH nella stessa esecuzione (una sola autenticazione fino al riavvio)" || { bad "conferma nella stessa esecuzione (rc=$rc)"; tail -8 $IT/out.txt; }
rm -f $IT/nuovo-login
# Invio senza nuovo login: nuova attesa; fine dell'input: sosta (nessun ciclo infinito)
fresh; echo "0 0 10.0.0.2:22 10.0.0.9:50000" > $IT/ss.txt
rc=$(timeout 60 bash -c "printf 'SI\n\n' > $IT/tty; OPS_INSTALLA_TEST_ROOT=$IT bash $RUNNER > $IT/out.txt 2>&1 < /dev/null; echo \$?")
[ "$rc" = 5 ] && [ "$(grep -c 'Apri ORA un NUOVO login' $IT/out.txt)" -ge 2 ] && ! grep -q -- '--confirm' $IT/calls \
  && pass "Invio senza nuovo login: nessuna conferma, nuova richiesta, poi sosta (esito 5)" || { bad "Invio senza login (rc=$rc)"; tail -6 $IT/out.txt; }
# riavvio con aggiornamenti in attesa: ops-maint attended, poi controlli dopo l'avvio
fresh; install -m 0600 /dev/null $IT/var/lib/ops-bootstrap/installa.state
for id in 0 1 3 4 5 6 7 9 10 10b 11.1 12; do echo "$id fatto 2026-10-04T00:00:00Z prova" >> $IT/var/lib/ops-bootstrap/installa.state; done
mkdir -p $IT/usr/local/sbin; printf '#!/bin/bash\necho "ops-maint $*" >> "$OPS_INSTALLA_TEST_ROOT/calls"\ntouch "$OPS_INSTALLA_TEST_ROOT/var/lib/ops-maint/postboot-pending"\n' > $IT/usr/local/sbin/ops-maint
chmod +x $IT/usr/local/sbin/ops-maint; touch $IT/var/run/reboot-required
rc=$(oi 'SI\n')
[ "$rc" = 5 ] && [ "$(calls)" = "install-maint enable postboot|ops-maint attended" ] && grep -qE '^12.4 attesa-riavvio .*attended' $IT/var/lib/ops-bootstrap/installa.state \
  && pass "riavvio con aggiornamenti in attesa: ops-maint attended, sosta (esito 5)" || { bad "attended (rc=$rc)"; calls; tail -5 $IT/out.txt; }
rm -f $IT/var/lib/ops-maint/postboot-pending $IT/var/run/reboot-required; echo boot-2 > $IT/boot_id; : > $IT/calls
rc=$(oi 'APPROVO\n')
[ "$rc" = 0 ] && grep -q '^verifiche-base.sh dopo-riavvio' $IT/calls && pass "dopo il riavvio di ops-maint attended: controlli e completamento" || { bad "dopo attended (rc=$rc)"; calls; }
rm -rf $IT/usr

# parametri: tutti i problemi in una volta, nessun passo
fresh; sed -i 's|^PROFILO=.*|PROFILO=""|; s|^LAN_CIDR=.*|LAN_CIDR=""|; s|^ESCLUSIONI=.*|ESCLUSIONI="6 10.3"|' $HC
rc=$(oi 'SI\n')
[ "$rc" = 3 ] && [ ! -e $IT/calls ] && grep -q 'PROFILO vuoto' $IT/out.txt && grep -q 'LAN_CIDR vuoto' $IT/out.txt && grep -q "'6' non ammesso" $IT/out.txt \
  && pass "parametri incompleti: elenco unico, nessun passo (esito 3)" || { bad "parametri (rc=$rc)"; tail -8 $IT/out.txt; }
rm -rf $IT /tmp/it-dati
