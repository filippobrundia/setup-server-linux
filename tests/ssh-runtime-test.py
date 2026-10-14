#!/usr/bin/env python3
import pathlib,subprocess,tempfile,os
src=(pathlib.Path(__file__).resolve().parent.parent/'payload/ops/docs/bootstrap/passo6-pacchetti.sh').read_text()
block=src.split('# ---- SSH_RUNTIME_READY\n',1)[1].split('# ---- SSH_RUNTIME_READY_END',1)[0]
for service,socket,start_ok,expected in [(False,True,True,0),(True,True,True,0),(False,True,False,3),(False,False,True,3)]:
 with tempfile.TemporaryDirectory() as d:
  p=pathlib.Path(d); state=p/'active'; log=p/'calls'
  if service:state.touch()
  code='''set -euo pipefail
die() { echo "$*" >&2; exit 3; }
systemctl() {
 printf '%s\\n' "$*" >> "$CALLS"
 if [ "$1" = start ]; then [ "$START_OK" = 1 ] || return 1; touch "$STATE"; return 0; fi
 case "${@: -1}" in ssh.service) test -f "$STATE";; ssh.socket) test "$SOCKET" = 1;; *) return 99;; esac
}
'''+block+'\n# Comme sshd -t, la suite exige le runtime actif.\ntest -f "$STATE"\n'
  r=subprocess.run(['bash','-c',code],env={**os.environ,'STATE':str(state),'CALLS':str(log),'START_OK':str(int(start_ok)),'SOCKET':str(int(socket))},capture_output=True,text=True)
  assert r.returncode==expected,(service,socket,start_ok,r.returncode,r.stderr)
  calls=log.read_text()
  if service:assert 'start ssh.service' not in calls
  if not socket and not service:assert 'start ssh.service' not in calls
  print('PASS',service,socket,start_ok,expected)
