#!/bin/bash
# Test del punto d'ingresso unico con sudo e agente simulati, terminale reale.
set -euo pipefail
PKG=${PKG:-/pkg}
id tester >/dev/null 2>&1 || useradd -m -s /bin/bash tester
usermod -aG sudo tester
mkdir -p /srv/ops/bin /srv/ops/docs/bootstrap /usr/local/lib/ops-bootstrap /home/tester/.npm-global/bin
cp "$PKG/payload/ops/bin/configura-server" /usr/local/bin/configura-server
cp "$PKG/payload/ops/bin/ops-host-check" /usr/local/bin/ops-host-check
cp "$PKG/payload/ops/docs/bootstrap/ops-installa" /usr/local/sbin/ops-installa
cp "$PKG/payload/ops/docs/bootstrap/"{rileva-parametri.sh,passi-comune.sh} /usr/local/lib/ops-bootstrap/
chmod 755 /usr/local/bin/configura-server /usr/local/bin/ops-host-check /usr/local/sbin/ops-installa
cp "$PKG/payload/ops/host.conf.tmpl" /srv/ops/host.conf
sed -i "s/@@HOST@@/$(hostname -s)/g;s/@@ADMIN@@/tester/g;s/^AGENTE=.*/AGENTE=\"agy\"/" /srv/ops/host.conf
printf '# Decisioni\n' > /srv/ops/docs/decisions.md
printf 'STATO: IN CORSO\n' > /srv/ops/docs/bootstrap/avanzamento.md
cat > /home/tester/.npm-global/bin/findmnt <<'EOF'
#!/bin/bash
[ "$1" != -n ] || exit 1
printf '/ 1000000000\n'
EOF
# Il rilevatore di root usa il PATH di sistema nel diagnostico, ma quello in --scrivi eredita la fixture disco unico.
cat > /home/tester/.npm-global/bin/sudo <<'EOF'
#!/bin/bash
set -e
[ -t 0 ] || exit 95
case $1 in
 /bin/bash) [[ "$2" = */bootstrap.sh ]] || exit 96; echo BOOT >> /home/tester/entry-trace ;;
 */bootstrap.sh) [ "$2" = --admin ] && [ "$3" = tester ] || exit 96; echo BOOT >> /home/tester/entry-trace ;;
 /usr/local/sbin/ops-installa)
  [ "$#" = 3 ] && [ "$2" = --parametri-sha256 ] || exit 97
  h=$(sha256sum /srv/ops/host.conf); [ "$3" = "${h%% *}" ] || exit 98
  echo INSTALL >> /home/tester/entry-trace
  printf 'STATO: COMPLETATO CON ESCLUSIONI\n' > /srv/ops/docs/bootstrap/avanzamento.md ;;
 *) exit 99 ;;
esac
EOF
cat > /srv/ops/bin/agente <<'EOF'
#!/bin/bash
[ -t 0 ] && [ "$#" = 2 ] && [ "$1" = --prepara ] && [ "$2" = agy ] || exit 91
echo LOGIN >> /home/tester/entry-trace
EOF
printf '#!/bin/bash\necho QUICK_CHECK\n' > /srv/ops/bin/quick-check
chmod +x /srv/ops/bin/* /home/tester/.npm-global/bin/*
chown -R tester:tester /srv/ops /home/tester/.npm-global
runuser -u tester -- git -C /srv/ops init -q
runuser -u tester -- git -C /srv/ops config user.name Fixture
runuser -u tester -- git -C /srv/ops config user.email fixture@invalid
runuser -u tester -- git -C /srv/ops add .
runuser -u tester -- git -C /srv/ops commit -qm fixture
runuser -u tester -- script -qec 'env PATH=/home/tester/.npm-global/bin:/usr/local/bin:/usr/bin:/bin bash /pkg/installa-server.sh --agente antigravity --profilo docker --esclusioni "7.1 10.3 11.2 12.8"' /home/tester/local-entry.log >/dev/null
[ "$(cat /home/tester/entry-trace)" = "$(printf 'BOOT\nLOGIN\nINSTALL')" ]
echo 'PASS ingresso locale: un comando, TTY conservato, nessuna chat'
mkdir -p /tmp/entry-archive/setup-server-linux-0.7.0
cp "$PKG/bootstrap.sh" /tmp/entry-archive/setup-server-linux-0.7.0/
chmod 755 /tmp/entry-archive/setup-server-linux-0.7.0/bootstrap.sh
tar -czf /tmp/entry-test.tar.gz -C /tmp/entry-archive setup-server-linux-0.7.0
h=$(sha256sum /tmp/entry-test.tar.gz); h=${h%% *}
printf '%s  setup-server-linux-0.7.0.tar.gz\n' "$h" > /tmp/entry-test-SHA256SUMS
cat > /home/tester/.npm-global/bin/curl <<'EOF'
#!/bin/bash
while [ $# -gt 0 ]; do case $1 in -o) dst=$2; shift 2 ;; http*) url=$1; shift ;; *) shift ;; esac; done
case $url in */setup-server-linux-0.7.0.tar.gz) cp /tmp/entry-test.tar.gz "$dst" ;; */SHA256SUMS) cp /tmp/entry-test-SHA256SUMS "$dst" ;; *) exit 93 ;; esac
EOF
chmod 755 /home/tester/.npm-global/bin/curl
runuser -u tester -- sh -c ': > /home/tester/entry-trace'
runuser -u tester -- script -qec "printf ignored | env PATH=/home/tester/.npm-global/bin:/usr/local/bin:/usr/bin:/bin bash /pkg/install.sh --sha256 $h --configura --agente antigravity --profilo docker --esclusioni '7.1 10.3 11.2 12.8'" /home/tester/public-entry.log >/dev/null
[ "$(cat /home/tester/entry-trace)" = "$(printf 'BOOT\nLOGIN\nINSTALL')" ]
echo 'PASS ingresso pubblico simulato: impronta verificata, TTY conservato da pipe, unico flusso'
echo ENTRY_TEST_OK

