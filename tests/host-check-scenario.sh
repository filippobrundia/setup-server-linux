#!/bin/bash
set -euo pipefail
apt-get update -qq >/dev/null
apt-get install -y -qq jq python3 iproute2 git shellcheck >/dev/null 2>&1
id tester >/dev/null 2>&1 || useradd -m -s /bin/bash tester
mkdir -p /srv/ops/docs/bootstrap /usr/local/lib/ops-bootstrap
install -m755 /pkg/payload/ops/bin/ops-host-check /usr/local/bin/ops-host-check
install -m644 /pkg/payload/ops/docs/bootstrap/rileva-parametri.sh /usr/local/lib/ops-bootstrap/rileva-parametri.sh
install -m755 /pkg/payload/ops/docs/bootstrap/ops-installa /usr/local/sbin/ops-installa
cp /pkg/payload/ops/docs/bootstrap/passi-comune.sh /srv/ops/docs/bootstrap/
cp /pkg/payload/ops/docs/bootstrap/passi-comune.sh /usr/local/lib/ops-bootstrap/
cp /pkg/payload/ops/host.conf.tmpl /srv/ops/host.conf
sed -i "s/@@HOST@@/$(hostname -s)/g;s/@@ADMIN@@/tester/g;s/@@OWNER@@/Tester/g;s/^LAN_CIDR=.*/LAN_CIDR=\"172.17.0.0\/16\"/;s/^DATA_MOUNT=.*/DATA_MOUNT=\"\/srv\"/;s/^PROFILO=.*/PROFILO=\"docker\"/;s/^ESCLUSIONI=.*/ESCLUSIONI=\"7.1 10.3 11.2 12.8\"/;s/^AGENTE=.*/AGENTE=\"agy\"/" /srv/ops/host.conf
sed -i 's/^SERVICES=.*/SERVICES="ssh cron ufw fail2ban docker"/' /srv/ops/host.conf
chown -R tester:tester /srv/ops
runuser -u tester -- /usr/local/bin/ops-host-check --rileva > /tmp/rileva.out
grep -q 'interfaccia: eth0' /tmp/rileva.out && grep -q 'gateway:' /tmp/rileva.out
runuser -u tester -- /usr/local/bin/ops-host-check --piano > /tmp/piano.out
grep -q 'Parametri completi' /tmp/piano.out
for op in --scrivi --rollback bash; do
 if runuser -u tester -- /usr/local/bin/ops-host-check "$op" >/dev/null 2>&1; then exit 1; fi
done
if runuser -u tester -- /usr/local/bin/ops-host-check --piano extra >/dev/null 2>&1; then exit 1; fi
if /usr/local/bin/ops-host-check --rileva >/dev/null 2>&1; then exit 1; fi
before=$(sha256sum /srv/ops/host.conf)
runuser -u tester -- /usr/local/bin/ops-host-check --rileva >/dev/null
[ "$before" = "$(sha256sum /srv/ops/host.conf)" ]
shellcheck /pkg/payload/ops/bin/ops-host-check
jq -e '(.permissions.allow | index("command(/usr/local/bin/ops-host-check --rileva)")) and (.permissions.allow | index("command(/usr/local/bin/ops-host-check --piano)")) and (.permissions.deny | index("command(sudo *)"))' /pkg/payload/home/antigravity-settings.json >/dev/null
# Il blocco della precedente 0.7.0 deve essere riconosciuto per l'aggiornamento.
printf '\ntouch /tmp/ops-plan-untrusted-probe\n' >> /srv/ops/docs/bootstrap/passi-comune.sh
runuser -u tester -- /usr/local/bin/ops-host-check --piano >/tmp/piano-protetto.out
[ ! -e /tmp/ops-plan-untrusted-probe ]
echo 'PASS piano: libreria del workspace modificata non eseguita'
printf 'HOST_CHECK_TEST_OK\n'

