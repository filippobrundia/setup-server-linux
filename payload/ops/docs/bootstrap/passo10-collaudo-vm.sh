#!/bin/bash
# Collaudo VM isolato: dati sintetici, Borg/borgmatic e logrotate reali.
# Invocare tramite sudo ops-installa --collaudo-backup-vm (integrita, lock e log).
# Nessuna configurazione di /etc, cron, host.conf o stato dei passi 10/10b.
set -euo pipefail
umask 077
[ "$(id -u)" = 0 ] || { echo 'ERRORE: serve il percorso ops-installa con sudo' >&2; exit 2; }
for c in borg borgmatic logrotate python3; do command -v "$c" >/dev/null || { echo "ERRORE: manca $c" >&2; exit 3; }; done
# mktemp sceglie un percorso nuovo e non riusa symlink o residui di altre esecuzioni.
WORK=$(mktemp -d /var/tmp/ops-backup-vm-XXXXXXXX)
chmod 0700 "$WORK"
cleanup() {
  rc=$?
  trap - EXIT
  if [ "$rc" != 0 ] && [ -f "$WORK/backup.log" ]; then tail -30 "$WORK/backup.log"; fi
  # Cancella solo il workspace appena creato e contenente dati sintetici del test.
  case "$WORK" in /var/tmp/ops-backup-vm-????????) rm -rf -- "$WORK" ;; *) echo 'ERRORE: percorso cleanup inatteso'; exit 3 ;; esac
  echo "ESITO COLLAUDO BACKUP VM=$rc; dati sintetici rimossi; nessun cron installato"
  exit "$rc"
}
trap cleanup EXIT
mkdir "$WORK/source" "$WORK/restore" "$WORK/cache" "$WORK/security"
export BORG_CACHE_DIR="$WORK/cache" BORG_SECURITY_DIR="$WORK/security"
export BORG_BASE_DIR="$WORK" BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
printf 'Dati sintetici foundation: prima versione\n' > "$WORK/source/prova.txt"
chmod 0640 "$WORK/source/prova.txt"
ln -s prova.txt "$WORK/source/link"
CONF=$WORK/config.yaml
{
  echo 'repositories:'; echo "  - path: $WORK/repo"
  echo 'source_directories:'; echo "  - $WORK/source"
  echo "archive_name_format: 'vm-test-{now:%Y-%m-%dT%H:%M:%S.%f}'"
  echo 'compression: zstd,8'
} > "$CONF"
echo '== Validazione configurazione temporanea'
borgmatic config validate -c "$CONF"
borg init --encryption=none "$WORK/repo"
backup() { borgmatic -c "$CONF" --verbosity 1 create >> "$WORK/backup.log" 2>&1; }
restore_check() {
  borgmatic -c "$CONF" extract --archive latest --destination "$WORK/restore"
  python3 - "$WORK" <<'CHECK'
from pathlib import Path
import os, stat, sys
w=Path(sys.argv[1]); src=w/'source'; dst=w/'restore'/str(src).lstrip('/')
assert dst.is_dir(), 'sorgente assente nel ripristino'
assert sorted(p.name for p in src.iterdir()) == sorted(p.name for p in dst.iterdir())
for a in src.iterdir():
 b=dst/a.name
 assert stat.S_IMODE(a.lstat().st_mode)==stat.S_IMODE(b.lstat().st_mode), 'permessi diversi'
 assert (a.lstat().st_uid,a.lstat().st_gid)==(b.lstat().st_uid,b.lstat().st_gid), 'proprietario diverso'
 if a.is_symlink(): assert b.is_symlink() and os.readlink(a)==os.readlink(b)
 else: assert not b.is_symlink() and a.read_bytes()==b.read_bytes(), 'contenuto diverso'
print('OK ripristino: contenuti, symlink, proprietario e permessi')
CHECK
}
echo '== Primo backup e ripristino'
backup
restore_check
# Ripristini successivi in cartella vuota: nessuna scrittura sugli originali.
rm -rf -- "$WORK/restore"; mkdir "$WORK/restore"
cat > "$WORK/logrotate.conf" <<ROTATE
$WORK/backup.log {
  size 1
  rotate 2
  missingok
  notifempty
  create 0600 root root
}
ROTATE
echo '== Rotazione isolata del log'
logrotate -s "$WORK/logrotate.state" -f "$WORK/logrotate.conf"
[ -s "$WORK/backup.log.1" ] && [ ! -s "$WORK/backup.log" ]
printf 'Seconda versione sintetica\n' >> "$WORK/source/prova.txt"
echo '== Secondo backup e ripristino'
backup
restore_check
[ -s "$WORK/backup.log" ]
[ "$(borg list --short "$WORK/repo" | wc -l)" -eq 2 ]
borg check "$WORK/repo"
echo 'COLLAUDO BACKUP VM SUPERATO: due archivi, due ripristini, rotazione e integrita'
echo 'Non prova copertura, restore dei dati reali, offsite o pianificazione notturna.'
