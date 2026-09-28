# Segreti nei container senza esporli a `docker inspect`

**Stato:** verificato (Docker Compose v5, 2026-09).

- Le variabili dichiarate in `environment:` del Compose sono leggibili con `docker inspect` da chiunque usi Docker.
- Se l'applicazione non supporta varianti `_FILE`, passare i segreti come **secrets** di Compose (file in
  `/run/secrets/…`) ed esportarli solo dentro il processo con un `entrypoint` minimo, per esempio:
  `export VAR="$$(cat /run/secrets/nome)"; exec <entrypoint originale> "$$@"` (in Compose `$$`). Impostando
  `entrypoint` va ridichiarato anche `command`, perché Compose azzera quello dell'immagine.
- Un file segreto letto da due utenti diversi (per esempio uid 1000 e l'utente di PostgreSQL): permessi 0644 in una
  cartella 0700 sull'host.
- Verifica: confrontare i valori con `docker inspect` e con i log **senza stamparli** (per esempio `grep -qF`).
- Limite: il processo e i suoi figli (per esempio un agente eseguito localmente) possono leggere `/run/secrets`:
  isolare altrove i processi non fidati.
