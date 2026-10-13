#!/bin/bash
# Git reale locale; errore di rete simulato. Nessun token o modello.
set -euo pipefail
PKG=${PKG:-/pkg}
C=$(mktemp -d)
trap 'rm -rf "$C"' EXIT
mkdir -p "$C/src" "$C/fakebin"
git init -q "$C/src"
git -C "$C/src" config user.name Fixture
git -C "$C/src" config user.email fixture@invalid
printf '# Indice\n' > "$C/src/INDEX.md"
git -C "$C/src" add .; git -C "$C/src" commit -qm fixture
git clone -q --bare "$C/src" "$C/remote"
branch=$(git -C "$C/src" branch --show-current)
printf 'KB_DIR="%s/local"\nKB_REMOTE="%s/remote"\nKB_BRANCH="%s"\nKB_SERVER_ID="test"\n' "$C" "$C" "$branch" > "$C/kb.conf"
KB_CONF="$C/kb.conf" bash "$PKG/payload/ops/bin/kb" init > "$C/init-out"
KB_CONF="$C/kb.conf" bash "$PKG/payload/ops/bin/kb" sync --quiet --strict
REAL_GIT=$(command -v git); export REAL_GIT
cat > "$C/fakebin/git" <<'MOCK'
#!/bin/bash
for a in "$@"; do
 if [ "$a" = fetch ]; then echo 'simulated network error' >&2; exit 128; fi
done
exec "$REAL_GIT" "$@"
MOCK
chmod +x "$C/fakebin/git"
PATH="$C/fakebin:$PATH" KB_CONF="$C/kb.conf" bash "$PKG/payload/ops/bin/kb" sync --quiet > "$C/out" 2>&1
if PATH="$C/fakebin:$PATH" KB_CONF="$C/kb.conf" bash "$PKG/payload/ops/bin/kb" sync --quiet --strict > "$C/out" 2>&1; then
 echo 'Falso successo strict con rete assente'; exit 1
fi
printf 'KB_REMOTE=""\n' > "$C/empty.conf"
KB_CONF="$C/empty.conf" bash "$PKG/payload/ops/bin/kb" sync --quiet
if KB_CONF="$C/empty.conf" bash "$PKG/payload/ops/bin/kb" sync --strict > "$C/out" 2>&1; then exit 1; fi
echo 'KB_STRICT_TEST_OK: Git locale reale, compatibilita ordinaria e rifiuto dei falsi successi'
