# Artefatti di riferimento collaudati

Copie **esatte** dei file collaudati il 2026-09-28 (sigillo del progetto BrundIA, immagini `runner:codex-0.155.1-4`
ed `egress-proxy:1`); impronte in `SHA256SUMS`. Usarli come punto di partenza, non ripartire dalle versioni precedenti
(che avevano i difetti descritti in [../README.md](../README.md)).

| File | Funzione |
|---|---|
| `runner/Dockerfile` | base `node:24-trixie-slim` fissata per digest, OpenSSH, Codex a versione fissata, utente 1001 |
| `runner/sshd_config` | sshd non root sulla 2222, solo chiave, nessun inoltro, `ForceCommand runner-session` |
| `runner/runner-common.sh` | riconosce i processi di un'esecuzione e se hanno ancora una sessione SSH aperta; chiude un'esecuzione |
| `runner/runner-session.sh` | per ogni comando SSH: segna l'attività; a ogni nuova esecuzione chiude le precedenti non più collegate |
| `runner/runner-janitor.sh` | chiude le esecuzioni inattive da `RUNNER_JANITOR_GRACE` secondi senza sessione aperta |
| `runner/runner-proxy.sh` | `/etc/profile.d`: uscita solo tramite `egress-proxy:3128` |
| `runner/entrypoint.sh` | chiave pubblica autorizzata da variabile, pulitore in background, sshd |
| `egress-proxy/proxy.mjs` | solo `CONNECT` 443 verso host ammessi, mai IP diretti o destinazioni private; registra solo host ed esito |
| `compose-estratto.yaml` | servizi, reti, limiti e mount da aggiungere al Compose |

Verifica: `sha256sum -c SHA256SUMS` in questa cartella. Se il progetto modifica questi file, deve rieseguire i test
([../test/](../test/README.md)) e, se la modifica è collaudata, aggiornare qui copie e impronte.
