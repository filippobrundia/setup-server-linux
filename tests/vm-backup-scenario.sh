#!/bin/bash
# Solo in container sacrificabile, come root: Borg/borgmatic/logrotate reali.
set -euo pipefail
PKG=${PKG:-/pkg}
HELPER=$PKG/payload/ops/docs/bootstrap/passo10-collaudo-vm.sh
before=$(find /var/tmp -maxdepth 1 -name 'ops-backup-vm-*' | sort)
snapshot() {
 for d in /etc/cron.d /etc/borgmatic /etc/logrotate.d; do
  if [ -e "$d" ]; then find "$d" -type f -exec sha256sum {} +; fi
 done | sort
}
snapshot > /tmp/vm-before
bash "$HELPER" > /tmp/vm-backup.log 2>&1 || { cat /tmp/vm-backup.log; exit 1; }
grep -q 'COLLAUDO BACKUP VM SUPERATO' /tmp/vm-backup.log
[ "$(grep -c 'OK ripristino:' /tmp/vm-backup.log)" = 2 ]
grep -q 'ESITO COLLAUDO BACKUP VM=0' /tmp/vm-backup.log
[ "$before" = "$(find /var/tmp -maxdepth 1 -name 'ops-backup-vm-*' | sort)" ]
snapshot > /tmp/vm-after; cmp /tmp/vm-before /tmp/vm-after
echo 'PASS backup VM reale: due archivi, restore e rotazione; nessuna configurazione cron/borgmatic/logrotate modificata'
# Inietta un guasto nel backup, non in installazioni o host; il codice non va mascherato.
mkdir -p /tmp/vm-fake
printf '#!/bin/bash\ncase " $* " in *" create "*) exit 37 ;; esac\nexec /usr/bin/borgmatic "$@"\n' > /tmp/vm-fake/borgmatic
chmod +x /tmp/vm-fake/borgmatic
rc=0; PATH=/tmp/vm-fake:$PATH bash "$HELPER" > /tmp/vm-fail.log 2>&1 || rc=$?
[ "$rc" = 37 ]; grep -q 'ESITO COLLAUDO BACKUP VM=37' /tmp/vm-fail.log
[ "$before" = "$(find /var/tmp -maxdepth 1 -name 'ops-backup-vm-*' | sort)" ]
echo 'PASS errore reale 37 conservato e dati sintetici rimossi'
bash "$HELPER" > /tmp/vm-retry.log 2>&1 || { cat /tmp/vm-retry.log; exit 1; }
grep -q 'COLLAUDO BACKUP VM SUPERATO' /tmp/vm-retry.log
echo 'PASS ripetizione dopo errore senza residui o interventi manuali'
