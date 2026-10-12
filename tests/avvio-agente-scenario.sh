#!/bin/bash
# CLI finti: il login Codex esistente non si ripete; nessuna chiamata al modello.
set -euo pipefail
PKG=${PKG:-/pkg}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ops/docs/bootstrap" "$T/bin" "$T/home/.npm-global/bin"
printf 'STATO: COMPLETATO CON ESCLUSIONI\n' > "$T/ops/docs/bootstrap/avanzamento.md"
printf 'AGENTE="codex"\n' > "$T/ops/host.conf"
printf '#!/bin/bash\ncase $1 in --stato) echo "agy|Altro|1|conforme|fatto|" ;; --ambiente) exit 0 ;; --verify) echo "codex: verifica OK" ;; *) exit 99 ;; esac\n' > "$T/bin/cli-update"
cat > "$T/home/.npm-global/bin/codex" <<'EOF'
#!/bin/bash
case "$*" in
 'login status') echo STATUS >> "$TRACE"; exit 0 ;;
 'login --device-auth') echo LOGIN_DUPLICATO >> "$TRACE"; exit 1 ;;
 '') echo SESSIONE >> "$TRACE"; exit 0 ;;
 *) exit 99 ;;
esac
EOF
chmod +x "$T/bin/cli-update" "$T/home/.npm-global/bin/codex"
: > "$T/input"
HOME="$T/home" TRACE="$T/trace" OPS_DIR="$T/ops" OPS_HOSTCONF="$T/ops/host.conf" OPS_CLI_UPDATE="$T/bin/cli-update" AGENTE_TTY="$T/input" bash "$PKG/payload/ops/bin/agente" codex > "$T/out" 2>&1
! grep -q LOGIN_DUPLICATO "$T/trace"
grep -q '^SESSIONE$' "$T/trace"
echo 'PASS login Codex diretto riconosciuto anche con stato riepilogativo incompleto'
python3 - "$PKG" <<'PYTEST'
import importlib.util,json,sys,tomllib
from pathlib import Path
r=Path(sys.argv[1])
spec=importlib.util.spec_from_file_location('migrate',r/'payload/ops/bin/gemini-policy-migrate.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
base=(r/'payload/home/gemini-ops-policy.toml').read_text()
out=m.migrate({'tools':{'allowed':['run_shell_command(git status)','run_shell_command(echo "prova")']}},base)
rules=tomllib.loads(out)['rule']
assert any(x.get('commandPrefix')=='sudo' and x['decision']=='deny' for x in rules)
assert any(x.get('commandPrefix')=='echo "prova"' and x['decision']=='allow' for x in rules)
rerun=tomllib.loads(m.migrate({},base,out))['rule']
assert any(x.get('commandPrefix')=='echo "prova"' for x in rerun)
try:m.migrate({'tools':{'allowed':['regola-personale-non-convertibile']}},base)
except ValueError:pass
else:raise AssertionError('regola non convertibile accettata')
assert 'allowed' not in json.loads((r/'payload/home/gemini-settings.json').read_text())['tools']
print('PASS migrazione policy Gemini: TOML valido, permessi personali conservati, sudo negato, errore su regole non convertibili')
PYTEST
bash -n "$PKG/bootstrap.sh" "$PKG/payload/ops/bin/agente" "$PKG/payload/ops/docs/bootstrap/passo7-impostazioni.sh"
shellcheck -S warning "$PKG/bootstrap.sh" "$PKG/payload/ops/bin/agente" "$PKG/payload/ops/docs/bootstrap/rileva-parametri.sh" "$PKG/payload/ops/docs/bootstrap/passo7-impostazioni.sh" "$PKG/payload/ops/docs/bootstrap/ops-installa"
echo AVVIO_AGENTE_TEST_OK
