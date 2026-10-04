# Controllo rapido

Da eseguire a inizio sessione, in sola lettura e senza sudo:

```bash
/srv/ops/bin/quick-check
```

Stampa una riga per controllo (`OK` / `ATTENZIONE` / `ERRORE`) e un esito finale.
Exit code: `0` tutto ok, `1` attenzioni, `2` errori. Riportare **solo** le righe non OK, oppure "tutto ok" in
una riga. Cosa controllare è scritto in `/srv/ops/host.conf` (nessuna credenziale): si aggiorna, con commit,
quando la macchina cambia.

## Cosa controlla

| Area | Controllo | Parametro in `host.conf` | Soglie |
|---|---|---|---|
| Configurazione iniziale | `docs/bootstrap/avanzamento.md` con `STATO: IN CORSO` | — | attenzione |
| Dischi | punti di montaggio presenti e occupazione | `MOUNTS` | attenzione ≥ 80%, errore ≥ 90% |
| Servizi | unit attive; nessuna unit fallita; `borgmatic.timer` disabilitato (se c'è il backup) | `SERVICES` | — |
| Docker | container previsti in esecuzione, nessuno in riavvio continuo, nessuno inatteso (solo se Docker c'è); amministratore fuori dal gruppo `docker`: senza container previsti basta `docker.service` attivo, con container previsti l'elenco non è leggibile ed è un errore | `CONTAINERS` | — |
| Tunnel | connessioni pronte del tunnel in uscita (solo se configurato) | `TUNNEL_READY_URL` | almeno 1 |
| Snapshot SQLite | ultima riga `sqlite-snapshots` nel log di borgmatic: esito, numero di database, età | `SQLITE_SNAPSHOTS`, `BORG_LOG` | attenzione > 26 h, errore > 50 h |
| Archivio Borg | ultimo archivio `<host>-…` e run di borgmatic senza errori, età; dopo la rotazione notturna, se il log corrente non ha ancora un archivio, si legge `<BORG_LOG>.1` | `BORG_REPO`, `BORG_LOG` | attenzione > 26 h, errore > 50 h |
| Copia remota | ultimo avvio da cron (journal) e nessun fallimento finale nel log, età | `OFFSITE`, `OFFSITE_LOG`, `OFFSITE_CRON_MATCH` | attenzione > 26 h, errore > 50 h |
| Journal | righe con priorità `err` nelle ultime 24 ore | — | attenzione se presenti |
| Manutenzione | esito di unattended-upgrades; riavvio richiesto (attenzione dopo 14 giorni); `hold` (errore); verifica post-riavvio mancante; timer e approvazione della finestra; rinvii ripetuti; aggiornamenti CLI falliti; monitoraggio esterno | — | vedi `manutenzione.md` |

Backup non ancora configurato (`BORG_REPO` vuoto) o copia remota assente (`OFFSITE` vuoto) sono **attenzioni**:
normali durante la configurazione iniziale, da risolvere prima del collaudo finale.

`quick-check --gate` esegue solo dischi, servizi (ignorando le unit `ops-*`), Docker, tunnel e backup: è il
controllo di salute usato dalla manutenzione automatica, che così non viene bloccata dai propri avvisi.

I backup girano ogni notte: 26 ore significa "una notte in ritardo", 50 ore "due notti perse".

## Se qualcosa non è OK

- **Snapshot SQLite fallito** → il backup di quella notte è stato interrotto di proposito; dettagli nel file
  `STATUS` della cartella degli snapshot (root).
- **Archivio Borg vecchio o con errori** → `tail -50 /var/log/borgmatic.log`.
- **Copia remota fallita** → `tail -30` del log indicato da `OFFSITE_LOG`. Un errore al primo tentativo seguito
  da un successo non è un problema; lo è se falliscono tutti e 3 i tentativi.
- **Container o servizio fermo** → `sudo docker logs --tail 50 <container>` / `systemctl status <servizio>`.

Il controllo non modifica nulla. Ogni intervento correttivo segue le regole operative di `AGENTS.md`.
Per le prove, `OPS_DIR` sostituisce `/srv/ops` e `MAINT_STATE` la cartella della manutenzione.
