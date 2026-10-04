# setup-server-linux

Prepara un **Ubuntu Server LTS appena installato** per l'amministrazione con agenti, applicando la base collaudata
sul server di origine: regole (`AGENTS.md`), documenti, checklist, script di controllo, manutenzione e monitoraggio.
Versione: vedi `VERSION`.

> **Stato: pre-release, non pronta per la produzione.** La 0.3.0 è stata collaudata su una VM di laboratorio con
> **Ubuntu Server 26.04.1 LTS** (Hyper-V), con esito "collaudo locale completato con esclusioni"; la 0.4.0 integra le
> correzioni emerse da quel collaudo ed è provata in container (`ubuntu:24.04` e `ubuntu:26.04`, senza systemd).
> Da provare prima della produzione: installazione da zero della 0.4.0 su una VM pulita, copia remota con ripristino,
> `--gate` con uscita 0, rete stabile, riavvio con `ops-maint attended` e `ops-postboot`, timer automatici
> (sezione "Collaudo").

## Installazione (release identificata, integrità verificata)

Sulla macchina nuova, come **utente amministratore normale** creato dall'installer di Ubuntu (nel gruppo `sudo`,
non root), con l'impronta SHA-256 riportata nella pagina della release:

```bash
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.4.0/install.sh \
  | bash -s -- --sha256 <IMPRONTA> --check   # solo controllo: piano e conflitti, nessuna modifica
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.4.0/install.sh \
  | bash -s -- --sha256 <IMPRONTA>           # esecuzione (ripetibile)
```

`install.sh` rifiuta root, scarica l'archivio della release `v0.4.0`, lo confronta con `SHA256SUMS` della release e
con l'impronta passata a `--sha256`, lo estrae in `~/setup-server-linux-0.4.0` e avvia
`sudo bootstrap.sh --admin <utente>` (sudo chiede la password). Claude Code e il suo login restano nell'account
dell'amministratore. Opzione: `--owner "Nome"` (nome del proprietario usato nelle regole; di default il primo nome
del campo GECOS).

Alternativa manuale: scaricare `setup-server-linux-0.4.0.tar.gz` e `SHA256SUMS` dalla release,
`sha256sum -c SHA256SUMS`, estrarre e lanciare `sudo ./bootstrap.sh --admin "$USER" [--check]`.

Poi, in un **nuovo** terminale: `claude` → completare il login personale. L'agente parte in `/srv/ops`, trova
`docs/bootstrap/avanzamento.md` con `STATO: IN CORSO` e prosegue con la checklist secondo `AGENTS.md`.

Sistemi: Ubuntu Server LTS; collaudo su macchina reale con **Ubuntu 26.04** (VM), prove automatiche in container
24.04 e 26.04. Su 26.04 il client NTP predefinito è chrony (accettato dalla checklist).

## Novità della 0.4.0 (correzioni dal collaudo della VM, 2026-10-04)

| Correzione | Dove |
|---|---|
| VERIFY delle unit `ops-*` senza filtro di `systemctl` (su 26.04 un filtro senza corrispondenze esce con 1 e fermava il bootstrap prima della Knowledge Base) | `bootstrap.sh` |
| `kb status` letto in una variabile con controllo del codice di uscita (niente `\| head`, niente "Broken pipe"); se fallisce la fase KB non è completata (esito 4) | `bootstrap.sh` |
| `quick-check`: Docker senza gruppo `docker` (OK se nessun container previsto e servizio attivo); archivio Borg letto dal log ruotato | `bin/quick-check` |
| Rotazione di `/var/log/borgmatic.log` (`delaycompress`) | `maint/templates/logrotate-borgmatic` |
| Nessun amministratore nel gruppo `docker` (accesso al socket = root senza password) | checklist 5 e 8.1, `docs/decisions.md` |
| `borgmatic.timer` mascherato durante l'installazione (il postinst di borgmatic 2.0 lo avvia); Docker mascherato finché `daemon.json` non è validato; `REQUIRED_UNITS` modificato solo sulla riga di assegnazione; orario con chrony | checklist 6, 7.5, 8.1, 10.2 |
| Sudo in un terminale vero, non con `! sudo` di Claude Code | `AGENTS.md` |
| Script dei passi 3, 6–10 e 12, parametrizzati con `host.conf` (nuova chiave `DATA_MOUNT`) e `/etc/os-release` | `docs/bootstrap/passo*.sh` |

Le scelte della VM di laboratorio (reti private al posto di `LAN_CIDR`, `"ip": "127.0.0.1"` in `daemon.json`,
`source_directories_must_exist`, layout a disco unico, valori fissi di `REQUIRED_UNITS`) **non** sono trasferite.

## Knowledge Base condivisa tra server

La conoscenza tecnica verificata sta in un **repository separato e condiviso**,
`filippobrundia/server-knowledge-base` (privato), con copia locale in `/srv/ops/knowledge-base` gestita dallo
strumento della foundation `/srv/ops/bin/kb`. Ogni server la consulta prima di intervenire e aggiunge ciò che impara
come **record** indipendenti (APPEND ONLY); le regole per gli amministratori sono in `AGENTS.md` (SYNC BEFORE WORK,
KNOWLEDGE FIRST, LEARN & CONSOLIDATE, VERIFY BEFORE PUBLISH, APPEND ONLY).

| Comando | Effetto |
|---|---|
| `kb sync` | recupera i record degli altri server; non tocca il lavoro locale; senza rete usa la copia locale (e lo dichiara); mai modifiche ai programmi installati, mai esecuzione di script della KB |
| `kb new "Titolo"` → `kb validate` → `kb publish` | nuovo record `RECORD-<data>-<server>-<casuale>`: metadati e sezioni obbligatorie, collegamenti, assenza di segreti e di dati riservati, pura aggiunta, recupero degli altri, push senza force (se respinto: recupero e nuovo tentativo) |
| `kb status`, `kb index`, `kb search` | stato della copia, indice locale dei record (non versionato), ricerca |
| `kb schedule on` | sincronizzazione leggera ogni 6 ore (crontab dell'amministratore) |

**Primo recupero su un server nuovo (repository privato).** Il bootstrap crea una **deploy key** del server
(`~/.ssh/kb_deploy`), verifica la chiave host di GitHub e tenta `kb init`. Senza autorizzazione o senza rete si
ferma con **esito 4** e il messaggio "KNOWLEDGE BASE NON RECUPERATA", stampando la chiave pubblica: il proprietario la
registra nel repository (Settings → Deploy keys; con scrittura solo se il server deve pubblicare), poi
`/srv/ops/bin/kb init` oppure `sudo bootstrap.sh --admin <utente> --knowledge-base-only`. Nessun token nel pacchetto.

`--knowledge-base-only` aggiorna solo strumento, configurazione e copia della Knowledge Base (nessun pacchetto,
agente, home o manutenzione). Opzioni: `--kb-remote URL`, `--kb-id NOME` (nome tecnico non sensibile del server).
Una copia incorporata della versione 0.2.0 viene spostata in `knowledge-base.v0.2.0-<data>` (conservata).

Il pacchetto ricrea la **foundation e la sua conoscenza**, non le applicazioni: nessuna installazione automatica di
ciò che la Knowledge Base descrive. Dati, segreti e configurazione per ripristinare una specifica istanza restano
nei backup e nei repository del relativo progetto.

**Protezione lato GitHub.** Con il piano gratuito un repository privato non ammette regole di protezione del ramo:
le modifiche distruttive sono impedite dallo strumento `kb` e dall'hook `pre-push` di ogni copia, mentre il workflow
`append-only` del repository le **rileva** e le segnala (non può impedirle).

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
| installa i file della manutenzione con `/srv/ops/maint/install-maint install` | installare applicazioni, Docker, backup, agenti applicativi (Docker e backup li installano gli script dei passi, lanciati dall'amministratore durante la checklist) |

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
| `payload/ops/maint/` | `ops-maint` (script root della finestra), unit `ops-*`, `install-maint`, modelli di backup/cron/logrotate/Docker |
| `payload/ops/docs/bootstrap/passo*.sh` | script dei passi della checklist (PRECHECK, BACKUP, MODIFICA, VERIFY, `--dry-run`, `--rollback`), lanciati con sudo dall'amministratore |
| `payload/home/` | adattatori per la home dell'amministratore |
| `payload/ops/bin/kb`, `payload/ops/kb.conf.tmpl` | strumento e configurazione della Knowledge Base condivisa |
| `tests/kb-scenario.sh` | collaudo dello strumento kb con un repository remoto fittizio e due copie |
| `tests/` | collaudo in container (`run-container-test.sh`, `scenario.sh`) |

Differenze rispetto al server di origine (solo parametrizzazione): nomi fissi `ops-*` al posto di `servern100-*`,
parametri della macchina in `/srv/ops/host.conf` (utente) e `/etc/ops-maint.conf` (root, letto senza eseguirlo),
`install-maint` al posto di `maint/install.sh` (che non viene distribuito), Node.js 22 (minimo dichiarato da
Claude Code). Non distribuiti: dati, credenziali, memorie, cronologia, autorizzazioni operative del server di origine (la
finestra va approvata per ogni macchina), `sqlite-snapshots.sh` (file root del server di origine non ancora estratto e
verificato: va estratto con sudo, riletto e parametrizzato prima di includerlo).

## Collaudo

**Fatto — in container (0.4.0).** `tests/run-container-test.sh` (Docker, container usa e getta senza systemd;
`IMAGE=ubuntu:26.04` per la 26.04): **124/124 prove superate sia su `ubuntu:24.04` sia su `ubuntu:26.04`**. Comprendono le prove
della 0.3.0 (distribuzione, idempotenza, conflitti, Knowledge Base condivisa su un repository remoto fittizio, scenario
`tests/kb-scenario.sh` 34/34) e i casi nuovi: A1 con un `systemctl` simulato come quello di 26.04 (difetto della 0.3.0
riprodotto, bootstrap con esito 0, errore reale con esito 3), A2 con `kb status` di 200000 righe e con errore (esito 4),
`quick-check` con log corrente, ruotato, senza archivio e con errori e con Docker senza gruppo `docker`, rotazione
reale del modello logrotate, lettore di `host.conf` (mai eseguito, valori non validi rifiutati), passo 3 completo
(dry-run, creazione, ripetizione, disco in fstab non montato, rollback), configurazione del passo 10 validata da
borgmatic reale, derivazione di `REQUIRED_UNITS` del passo 9, arresto degli script senza parametri, shellcheck.
Gli script dei passi 6, 7, 8, 10, 10b e 12 richiedono systemd, APT e rete reali: in container solo controlli
parziali.

**Fatto — VM di laboratorio (0.3.0 con le correzioni di `bootstrap.sh`, Ubuntu Server 26.04.1, Hyper-V,
2026-10-02/04):** bootstrap, passi 1–10 (backup locale e ripristino con zero differenze), Healthchecks con allarme
reale, verifiche 12.2 locale, 12.4 (riavvio normale), 12.5–12.7. Esclusi: copia remota (10.3, 11.1, 12.2 da remoto,
12.3), rete stabile (7.1). Gli script dei passi 0.4.0 derivano da quelli della VM, parametrizzati: la versione
parametrizzata non è ancora stata eseguita su una macchina reale.
**Fatto — sul server di origine** (fisico, Ubuntu 24.04): scenario `kb` e prove sul repository GitHub reale (0.3.0).

**Da provare su una VM pulita con Ubuntu Server 26.04 (installazione da zero della 0.4.0, senza correzioni manuali):**
1. `install.sh --check`, poi installazione: `bootstrap.sh` con esito 0 senza `--knowledge-base-only`, riepilogo KB
   senza "Broken pipe";
2. passo 6: `borgmatic.timer` mai avviato; passo 7.5 con chrony;
3. passo 8: Docker avviato solo dopo la validazione di `daemon.json`, amministratore fuori dal gruppo `docker`,
   `quick-check` senza ERRORE su Docker, `docker.service` in `REQUIRED_UNITS`;
4. passo 10: `/etc/logrotate.d/borgmatic` dal modello, `quick-check` trova l'archivio dopo una rotazione;
5. spegnimento: `journalctl -b -1 -u finalrd` (su 26.04 `finalrd.service` usciva con 73, senza conseguenze osservate);
6. agenti: indicazioni su sudo senza `! sudo`.

**Per la produzione servono inoltre:** copia remota con ripristino provato (10.3, 12.2 da remoto, 12.3),
`quick-check --gate` con uscita 0 (11.1), rete stabile (7.1), `ops-maint attended` con `ops-postboot`, attivazione e
prima esecuzione dei timer (12.8), `install.sh` dalla release pubblicata.
