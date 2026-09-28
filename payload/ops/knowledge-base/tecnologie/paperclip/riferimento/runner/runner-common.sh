# Funzioni comuni del runner (incluse da runner-session e runner-janitor).
RUNS=/work/.paperclip-runtime/runs
MARKS=/tmp/runner-activity
# run_pids ID: processi (escluso il chiamante) che usano la cartella dell'esecuzione come directory corrente o la
# citano negli argomenti (codex, ponte, tar di ripristino, ...).
run_pids() {
  _id=$1
  for _p in /proc/[0-9]*; do
    _n=${_p#/proc/}; [ "$_n" = "$$" ] && continue
    case "$(readlink "$_p/cwd" 2>/dev/null)" in "$RUNS/$_id"*) echo "$_n"; continue ;; esac
    _c=$(tr '\0' ' ' < "$_p/cmdline" 2>/dev/null)
    case "$_c" in *"$_id"*) echo "$_n" ;; esac
  done
}
# attached PID: vero se il processo discende da una sessione SSH ancora aperta (connessione di Paperclip viva).
# Un processo rimasto dopo la chiusura della connessione (esecuzione interrotta) viene riassegnato al pid 1.
attached() {
  _q=$1
  while [ -n "$_q" ] && [ "$_q" -gt 1 ] 2>/dev/null; do
    case "$(cat "/proc/$_q/comm" 2>/dev/null)" in sshd-session|sshd-auth) return 0 ;; sshd) [ "$_q" != 1 ] && return 0 ;; esac
    _q=$(awk '{print $4}' "/proc/$_q/stat" 2>/dev/null)
  done
  return 1
}
# run_attached ID: vero se almeno un processo dell'esecuzione ha ancora una sessione SSH aperta.
run_attached() { for _x in $(run_pids "$1"); do attached "$_x" && return 0; done; return 1; }
# end_run ID MOTIVO: termina i processi rimasti dell'esecuzione e rimuove cartella e marcatore.
end_run() {
  _pids=$(run_pids "$1")
  if [ -n "$_pids" ]; then kill -TERM $_pids 2>/dev/null; sleep 2; kill -KILL $(run_pids "$1") 2>/dev/null; fi
  rm -rf "$RUNS/$1" "$MARKS/$1" && echo "runner: chiusa l'esecuzione $1 ($2; processi terminati: $(echo $_pids | wc -w))" >&2
}
