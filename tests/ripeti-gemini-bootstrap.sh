#!/usr/bin/env bash
# Riprova le sezioni della suite influenzate dalla migrazione Gemini.
set -u
source <(awk '/^echo "== T12 / {exit} {print}' /pkg/tests/scenario.sh)
source <(awk '/^echo "== T13 / {copy=1} /^echo "== T14 / {exit} copy {print}' /pkg/tests/scenario.sh)
printf 'RISULTATO RIPETIZIONE: %s/%s\n' "$((N-FAILS))" "$N"
test "$FAILS" = 0
