#!/bin/bash
# Prova isolata orchestratore: passi privilegiati e login SIMULATI, nessun modello chiamato.
set -euo pipefail
PKG=${PKG:-/pkg}
C=/tmp/ops-config-test
U=cfgtest
id "$U" >/dev/null 2>&1 || useradd -m -s /bin/bash "$U"
mkdir -p "$C"/{srv/ops/{bin,docs/bootstrap},usr/local/{bin,sbin,lib/ops-bootstrap},fakebin}
cp "$PKG/payload/ops/docs/bootstrap/rileva-parametri.sh" "$C/usr/local/lib/ops-bootstrap/"
cp "$PKG/payload/ops/docs/bootstrap/ops-installa" "$C/usr/local/sbin/ops-installa"
cp "$PKG/payload/ops/docs/bootstrap/passi-comune.sh" "$C/srv/ops/docs/bootstrap/"
cp "$PKG/payload/ops/host.conf.tmpl" "$C/srv/ops/host.conf"
sed -i "s/@@HOST@@/$(hostname -s)/g;s/@@ADMIN@@/$U/g;s/^AGENTE=.*/AGENTE=\"agy\"/" "$C/srv/ops/host.conf"
printf '# Decisioni\n' > "$C/srv/ops/docs/decisions.md"
printf 'STATO: IN CORSO\n' > "$C/srv/ops/docs/bootstrap/avanzamento.md"
cat > "$C/usr/local/bin/ops-host-check" <<'EOF'
#!/bin/bash
set -e
case $1 in
 --rileva) OPS_DIR="$CT/srv/ops" exec /bin/bash "$CT/usr/local/lib/ops-bootstrap/rileva-parametri.sh" ;;
 --piano) OPS_INSTALLA_TEST_ROOT="$CT" exec /bin/bash "$CT/usr/local/sbin/ops-installa" --piano ;;
 *) exit 2 ;;
esac
EOF
cat > "$C/srv/ops/bin/agente" <<'EOF'
#!/bin/bash
if [ "$#" = 1 ]; then
 case $1 in claude|codex|agy|gemini) printf 'LAUNCH %s\n' "$1" >> "$CT/trace"; exit 0 ;; esac
fi
[ "$1" = --prepara ] && [ "$#" = 2 ] || exit 2
printf 'LOGIN %s\n' "$2" >> "$CT/trace"
exit "${SIM_LOGIN_RC:-0}"
EOF
# Fixture disco unico: i mount di file Docker non rappresentano un disco dati VM.
cat > "$C/fakebin/findmnt" <<'EOF'
#!/bin/bash
if [ "$1" = -n ]; then exit 1; fi
printf '/ 1000000000\n'
EOF
cat > "$C/fakebin/sudo" <<'EOF'
#!/bin/bash
[ "$#" = 3 ] && [ "$1" = "$CT/usr/local/sbin/ops-installa" ] && [ "$2" = --parametri-sha256 ] || exit 90
expected=$(sha256sum "$CT/srv/ops/host.conf"); expected=${expected%% *}
[ "$3" = "$expected" ] || exit 91
echo SUDO_INSTALLER >> "$CT/trace"
exit "${SIM_RC:-0}"
EOF
printf '#!/bin/bash\necho QUICK_CHECK\n' > "$C/srv/ops/bin/quick-check"
chmod +x "$C/usr/local/bin/ops-host-check" "$C/srv/ops/bin/"* "$C/fakebin/"*
chown -R "$U:$U" "$C"
runuser -u "$U" -- git -C "$C/srv/ops" init -q
runuser -u "$U" -- git -C "$C/srv/ops" config user.name Fixture
runuser -u "$U" -- git -C "$C/srv/ops" config user.email fixture@invalid
runuser -u "$U" -- git -C "$C/srv/ops" add .
runuser -u "$U" -- git -C "$C/srv/ops" commit -qm fixture
run_cfg() { runuser -u "$U" -- env CT="$C" OPS_CONFIG_TEST_ROOT="$C" SIM_RC="${SIM_RC:-0}" SIM_LOGIN_RC="${SIM_LOGIN_RC:-0}" /bin/bash "$PKG/payload/ops/bin/configura-server" "$@"; }
check_rc() { local want=$1; shift; set +e; run_cfg "$@" > "$C/out" 2>&1; local got=$?; set -e; [ "$got" = "$want" ] || { cat "$C/out"; echo "atteso=$want ottenuto=$got"; exit 1; }; }
check_rc 0 --profilo docker --esclusioni '7.1 10.3 11.2 12.8' --prepara
[ ! -e "$C/trace" ]
grep -q '^SERVICES="ssh cron ufw fail2ban docker"' "$C/srv/ops/host.conf"
echo 'PASS preparazione reale senza login o sudo'
for a in claude codex agy gemini; do
 sed -i "s/^AGENTE=.*/AGENTE=\"$a\"/" "$C/srv/ops/host.conf"
 : > "$C/trace"; chown "$U:$U" "$C/trace"
 check_rc 0
 [ "$(cat "$C/trace")" = "$(printf 'LOGIN %s\nSUDO_INSTALLER' "$a")" ]
 grep -q 'Codice reale installer: 0' "$C/srv/ops/docs/bootstrap/esito-configurazione.md"
 echo "PASS flusso comune per $a, nessuna chat interattiva"
done
: > "$C/trace"; chown "$U:$U" "$C/trace"; SIM_LOGIN_RC=1; check_rc 1; ! grep -q SUDO "$C/trace"; SIM_LOGIN_RC=0
echo 'PASS login fallito blocca installer'
SIM_RC=5; check_rc 5; grep -q 'rilancia configura-server' "$C/out"
SIM_RC=0; check_rc 0
echo 'PASS attesa riavvio e ripresa con parametri conservati'
SIM_RC=1; check_rc 1; grep -q 'Codice reale installer: 1' "$C/srv/ops/docs/bootstrap/esito-configurazione.md"; SIM_RC=0
echo 'PASS errore installer riportato senza falso successo'
check_rc 3 --profilo base
check_rc 3 --esclusioni '10.3'
check_rc 2 --comando-arbitrario
if /bin/bash "$PKG/payload/ops/bin/configura-server" --profilo docker >/dev/null 2>&1; then exit 1; fi
echo 'PASS cambio profilo, esclusioni incompatibili, argomenti arbitrari e root rifiutati'
# Terminale reale simulato: solo una scelta esplicita apre una chat, dopo installer.
: > "$C/trace"; chown "$U:$U" "$C/trace"
printf 'codex\n' | script -q -e -c "runuser -u $U -- env CT=$C OPS_CONFIG_TEST_ROOT=$C /bin/bash $PKG/payload/ops/bin/configura-server" /dev/null > "$C/menu-out" 2>&1
[ "$(grep -c '^SUDO_INSTALLER$' "$C/trace")" = 1 ]
[ "$(tail -n 1 "$C/trace")" = 'LAUNCH codex' ]
echo 'PASS scelta finale Codex dopo installer, senza seconda installazione'
: > "$C/trace"; chown "$U:$U" "$C/trace"
printf '\n' | script -q -e -c "runuser -u $U -- env CT=$C OPS_CONFIG_TEST_ROOT=$C /bin/bash $PKG/payload/ops/bin/configura-server" /dev/null > "$C/menu-out" 2>&1
! grep -q LAUNCH "$C/trace"
echo 'PASS termine senza chat: nessun agente avviato implicitamente'
shellcheck -S warning "$PKG/payload/ops/bin/configura-server" "$PKG/installa-server.sh" "$PKG/install.sh"
echo 'CONFIGURA_SERVER_TEST_OK'

