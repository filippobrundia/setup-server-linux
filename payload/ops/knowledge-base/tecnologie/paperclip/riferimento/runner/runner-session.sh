#!/bin/sh
# Ogni comando SSH passa di qui. Segna l'attività delle esecuzioni citate; all'inizio di una NUOVA esecuzione chiude
# subito le esecuzioni precedenti che non hanno più una sessione SSH aperta (processi rimasti terminati, file
# rimossi), così un incarico non trova i file del precedente. Poi esegue il comando invariato.
# Il runner è dedicato a un solo agente con una sola esecuzione alla volta (maxConcurrentRuns = 1).
# Non registra i comandi (contengono token temporanei); solo nel banco di prova (/etc/runner/audit) li registra.
. /usr/local/lib/runner-common.sh
mkdir -p "$MARKS"
ids=$(printf '%s' "${SSH_ORIGINAL_COMMAND:-}" | grep -oE 'runs/[0-9a-f-]{36}' | cut -d/ -f2 | sort -u)
new=0
for id in $ids; do [ -e "$MARKS/$id" ] || new=1; : > "$MARKS/$id"; done
if [ "$new" = 1 ] && [ -d "$RUNS" ]; then
  for d in "$RUNS"/*/; do
    [ -d "$d" ] || continue
    old=$(basename "$d")
    case " $(echo $ids) " in *" $old "*) continue ;; esac
    run_attached "$old" || end_run "$old" "nuova esecuzione" 2>>/tmp/runner-cleanup.log
  done
fi
if [ -f /etc/runner/audit ]; then
  { printf '=== %s\n' "$(date -u +%FT%T)"; printf '%s\n' "${SSH_ORIGINAL_COMMAND:-<shell>}"; } >> /tmp/runner-audit.log
fi
if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then exec /bin/sh -c "$SSH_ORIGINAL_COMMAND"; else exec /bin/sh -l; fi
