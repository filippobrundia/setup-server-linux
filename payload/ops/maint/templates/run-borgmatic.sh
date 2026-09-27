#!/usr/bin/env bash
# run-borgmatic.sh — avvia borgmatic dal cron delle 03:00 (unico scheduler dei backup).
# Installazione: sudo install -o root -g root -m 0750 run-borgmatic.sh /usr/local/bin/run-borgmatic.sh
set -euo pipefail
borgmatic --verbosity 1 --syslog-verbosity 1
