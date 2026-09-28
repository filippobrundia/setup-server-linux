#!/bin/sh
# Pulitore: chiude un'esecuzione (processi rimasti terminati; workspace, login di Codex e token temporanei rimossi)
# quando nessun suo processo ha più una sessione SSH aperta e nessun comando SSH la cita da RUNNER_JANITOR_GRACE
# secondi. Copre esecuzioni riuscite, fallite e interrotte (tempo scaduto, annullamento, connessione persa).
. /usr/local/lib/runner-common.sh
GRACE=${RUNNER_JANITOR_GRACE:-90}
while sleep 15; do
  [ -d "$RUNS" ] || continue
  now=$(date +%s)
  for d in "$RUNS"/*/; do
    [ -d "$d" ] || continue
    id=$(basename "$d")
    last=$(stat -c %Y "$MARKS/$id" 2>/dev/null || stat -c %Y "$d")
    [ $((now - last)) -ge "$GRACE" ] || continue
    run_attached "$id" || end_run "$id" "inattiva da ${GRACE}s"
  done
done
