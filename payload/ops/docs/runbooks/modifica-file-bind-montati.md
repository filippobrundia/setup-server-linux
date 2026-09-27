# Modificare file bind-montati nei container (es. Caddyfile)

**Problema verificato (2026-08-02)**: i file montati come singolo file in un container (es.
`/srv/docker/caddy/Caddyfile` → `/etc/caddy/Caddyfile`) sono legati all'**inode**. Strumenti che scrivono
un file nuovo e lo rinominano (`install`, `mv`, molti editor) creano un inode nuovo: il container resta
agganciato al vecchio e continua a servire la config precedente. `caddy reload` dall'interno **non basta**.

**Procedura**
1. Copia di sicurezza: `sudo cp -p <file> <file>.bak-AAAA-MM-GG`.
2. Prepara la nuova versione in un file temporaneo e validala (Caddy: `caddy validate`).
3. Sovrascrivi **in place** (stesso inode): `sudo cp <nuovo> <file>` (oppure `cat nuovo | sudo tee file`).
4. Ricarica il servizio (Caddy: `docker exec caddy caddy reload --config /etc/caddy/Caddyfile`).
5. Se è stato usato un rename (`install`/`mv`): `docker restart <container>` è obbligatorio.
6. Verifica che il container veda il contenuto nuovo (`docker exec caddy cat /etc/caddy/Caddyfile`).

Stessa cautela per qualunque bind di singolo file.
