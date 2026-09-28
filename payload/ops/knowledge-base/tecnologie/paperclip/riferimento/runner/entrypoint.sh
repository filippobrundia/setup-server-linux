#!/bin/sh
# Avvio: chiave host persistente (verifica stabile lato Paperclip), chiave pubblica autorizzata da variabile,
# pulitore in background, sshd in primo piano.
set -eu
[ -f /var/lib/runner-ssh/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -N '' -f /var/lib/runner-ssh/ssh_host_ed25519_key
install -d -m 0700 /home/agent/.ssh
printf '%s\n' "${AUTHORIZED_KEY:?manca AUTHORIZED_KEY}" > /home/agent/.ssh/authorized_keys
chmod 0600 /home/agent/.ssh/authorized_keys
/usr/local/bin/runner-janitor &
exec /usr/sbin/sshd -D -e -f /etc/runner/sshd_config
