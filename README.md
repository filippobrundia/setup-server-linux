# setup-server-linux

Prepara un **Ubuntu Server LTS appena installato** per l'amministrazione con agenti, applicando la base collaudata
sul server di origine: regole (`AGENTS.md`), documenti, checklist, script di controllo, manutenzione e monitoraggio.
Versione: vedi `VERSION`.

> **Stato: collaudato solo in container.** Le prove automatiche (sezione "Collaudo") girano in un container
> `ubuntu:24.04` senza systemd. **Non** sono ancora verificati su Ubuntu Server reale: systemd e attivazione delle
> unit, login di Claude Code e primo avvio dell'agente, riavvio presidiato, integrazione con Healthchecks,
> `install.sh`. Non usare in produzione prima di quel collaudo.

## Installazione (release identificata, integrità verificata)

Sulla macchina nuova, come **utente amministratore normale** creato dall'installer di Ubuntu (nel gruppo `sudo`,
non root), con l'impronta SHA-256 riportata nella pagina della release:

```bash
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.1.0/install.sh \
  | bash -s -- --sha256 <IMPRONTA> --check   # solo controllo: piano e conflitti, nessuna modifica
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.1.0/install.sh \
  | bash -s -- --sha256 <IMPRONTA>           # esecuzione (ripetibile)
```

`install.sh` rifiuta root, scarica l'archivio della release `v0.1.0`, lo confronta con `SHA256SUMS` della release e
con l'impronta passata a `--sha256`, lo estrae in `~/setup-server-linux-0.1.0` e avvia
`sudo bootstrap.sh --admin <utente>` (sudo chiede la password). Claude Code e il suo login restano nell'account
dell'amministratore. Opzione: `--owner "Nome"` (nome del proprietario usato nelle regole; di default il primo nome
del campo GECOS).

Alternativa manuale: scaricare `setup-server-linux-0.1.0.tar.gz` e `SHA256SUMS` dalla release,
`sha256sum -c SHA256SUMS`, estrarre e lanciare `sudo ./bootstrap.sh --admin "$USER" [--check]`.

Poi, in un **nuovo** terminale: `claude` → completare il login personale. L'agente parte in `/srv/ops`, trova
`docs/bootstrap/avanzamento.md` con `STATO: IN CORSO` e prosegue con la checklist secondo `AGENTS.md`.

## Requisito Node.js

Node.js **22** da NodeSource (`node_22.x`, chiave verificata per impronta), perché il pacchetto npm di Claude Code
lo richiede: `npm view @anthropic-ai/claude-code@stable version engines` → `2.1.274`,
`engines: { node: '>=22.0.0' }` (metadati del registro npm consultati il 2026-09-27). Ubuntu 24.04 fornisce Node.js 18.

## Cosa fa (e cosa no)

| Fa | Non fa |
|---|---|
| installa `git curl ca-certificates gnupg jq` e Node.js 22 da NodeSource (chiave verificata per impronta) | partizionare, formattare, montare dischi |
| crea `/srv/ops` (repository Git) con regole, adattatori, documenti, checklist, script, `host.conf` | toccare rete, SSH, firewall, utenti, hostname |
| installa Claude Code (npm, canale `stable`, autoaggiornamento disattivato) per l'amministratore | attivare timer o servizi: tutte le unit `ops-*` restano disabilitate |
| aggiunge nella home un blocco marcato in `~/.bash_aliases`, `~/CLAUDE.md` di solo rimando, le impostazioni di Claude | copiare istruzioni nella home (l'unica fonte è `/srv/ops/AGENTS.md`) |
| installa i file della manutenzione con `/srv/ops/maint/install-maint install` | installare applicazioni, Docker, backup, agenti applicativi |

Prima di cambiare qualcosa controlla tutto; al primo **conflitto** (file esistente diverso e non installato dal
pacchetto, `/srv/ops` estranea, impostazioni incompatibili) si ferma senza modifiche. Riesecuzioni: i file
identici si saltano, quelli del pacchetto non modificati si aggiornano, quelli compilati dall'agente (`AGENTS.md`,
`STATUS.md`, `host.conf`, documenti di sistema, avanzamento) non vengono mai sovrascritti. Log:
`/var/log/ops-bootstrap.log`. Il pacchetto si rifiuta di girare sul server di origine.

## Contenuto

| Percorso | Contenuto |
|---|---|
| `install.sh` | punto di ingresso pubblico: scarica la release, verifica l'integrità, avvia `bootstrap.sh` |
| `bootstrap.sh` | preparazione della macchina (avviato con sudo da `install.sh`) |
| `payload/ops/` | ciò che diventa `/srv/ops` (`*.tmpl` completati con hostname, utente, proprietario, data) |
| `payload/ops/maint/` | `ops-maint` (script root della finestra), unit `ops-*`, `install-maint`, modelli di backup/cron/Docker |
| `payload/home/` | adattatori per la home dell'amministratore |
| `tests/` | collaudo in container (`run-container-test.sh`, `scenario.sh`) |

Differenze rispetto al server di origine (solo parametrizzazione): nomi fissi `ops-*` al posto di `servern100-*`,
parametri della macchina in `/srv/ops/host.conf` (utente) e `/etc/ops-maint.conf` (root, letto senza eseguirlo),
`install-maint` al posto di `maint/install.sh` (che non viene distribuito), Node.js 22 (minimo dichiarato da
Claude Code). Non distribuiti: dati, credenziali, memorie, cronologia, autorizzazioni operative del server di origine (la
finestra va approvata per ogni macchina), `sqlite-snapshots.sh` (file root del server di origine non ancora estratto e
verificato: va estratto con sudo, riletto e parametrizzato prima di includerlo).

## Collaudo

**Fatto — solo in container.** `tests/run-container-test.sh` (Docker, immagine `ubuntu:24.04` usa e getta, senza
systemd): **52/52 prove superate** il 2026-09-27 su protezioni, `--check`, prima esecuzione, contenuto, idempotenza,
conflitti, aggiornamento del pacchetto, adattatori, script e shellcheck. Dopo quella esecuzione sono cambiati solo
testi, il nome del progetto e un controllo del test (lo scenario ora conta 51 prove); `install.sh` è stato aggiunto
dopo e **non è stato eseguito** in container.

**Da provare su una VM o macchina Ubuntu Server pulita, con systemd, prima dell'uso in produzione:**
1. `bootstrap.sh` su Ubuntu Server reale (pacchetti di `ubuntu-server` già presenti, `unattended-upgrades` attivo
   al primo avvio: attesa dei blocchi APT);
2. `install-maint install` con systemd: `daemon-reload`, tmpfiles, nessuna unit abilitata;
3. login di Claude Code e primo avvio dell'agente: riconoscimento della configurazione incompleta;
4. `install-maint enable postboot|window|cli-update` con i prerequisiti, `cli-update --verify` dopo il login;
5. riavvio presidiato (`ops-maint attended`) e `ops-postboot`;
6. `bin/healthchecks setup` e prova dell'allarme con un controllo reale.
