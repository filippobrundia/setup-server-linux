#!/bin/bash
# Solo simulazione del processo: il collaudo kernel reale resta sulla VM.
set -euo pipefail
PKG=${PKG:-/pkg}
C=$(mktemp -d)
trap 'rm -rf "$C"' EXIT
mkdir -p "$C/home/.npm-global/bin" "$C/ops"
touch "$C/ops/AGENTS.md"
printf '#!/bin/bash\nexit 98\n' > "$C/home/.npm-global/bin/claude"
cat > "$C/home/.npm-global/bin/bwrap" <<'MOCK'
#!/bin/bash
case $MODE in
 denied) echo 'apply-seccomp: write /proc/self/setgroups: Permission denied'; exit 1 ;;
 empty) echo 'bwrap started'; exit 0 ;;
 pass) echo CLAUDE_SANDBOX_VERIFICATA; exit 0 ;;
esac
MOCK
chmod +x "$C/home/.npm-global/bin/"*
for mode in denied empty; do
 if HOME="$C/home" MODE=$mode bash "$PKG/payload/ops/bin/claude-sandbox-check" "$C/ops" > "$C/out" 2>&1; then
  echo "Falso successo per $mode"; exit 1
 fi
done
HOME="$C/home" MODE=pass bash "$PKG/payload/ops/bin/claude-sandbox-check" "$C/ops" > "$C/out"
grep -qx CLAUDE_SANDBOX_VERIFICATA "$C/out"
echo 'CLAUDE_CHECK_SIMULATO_OK: errore helper e bwrap avviato senza prova non passano'
