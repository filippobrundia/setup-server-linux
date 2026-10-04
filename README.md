# setup-server-linux

Prepara un **Ubuntu Server LTS appena installato** per l'amministrazione con agenti, applicando la base collaudata
sul server di origine: regole (`AGENTS.md`), documenti, checklist, script di controllo, manutenzione e monitoraggio.
Versione: vedi `VERSION`.

> **Stato: pre-release, non pronta per la produzione.** La 0.4.0 è stata collaudata su una VM pulita con
> **Ubuntu Server 26.04.1 LTS** (Hyper-V), con esito "collaudo locale completato con esclusioni", ma con 29 richieste
> di password e 8 script locali. La 0.5.0 integra le correzioni di quel collaudo e introduce il **comando unico**
> `sudo ops-installa`; è provata in container (`ubuntu:24.04` e `ubuntu:26.04`, senza systemd). Da provare prima
> della produzione: il flusso unico da zero su una VM pulita (sezione "Collaudo").

## Installazione (release identificata, integrità verificata)

Sulla macchina nuova, come **utente amministratore normale** creato dall'installer di Ubuntu (nel gruppo `sudo`,
non root), con l'impronta SHA-256 riportata nella pagina della release:

```bash
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.5.0/install.sh \
  | bash -s -- --sha256 <IMPRONTA> --check   # solo controllo: piano e conflitti, nessuna modifica
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.5.0/install.sh \
  | bash -s -- --sha256 <IMPRONTA>           # esecuzione (ripetibile)
```

`install.sh` rifiuta root, scarica l'archivio della release `v0.5.0`, lo confronta con `SHA256SUMS` della release e
con l'impronta passata a `--sha256`, lo estrae in `~/setup-server-linux-0.5.0` e avvia
`sudo bootstrap.sh --admin <utente>` (sudo chiede la password). Claude Code e il suo login restano nell'account
dell'amministratore. Opzione: `--owner "Nome"` (nome del proprietario usato nelle regole; di default il primo nome
del campo GECOS).

Alternativa manuale: scaricare `setup-server-linux-0.5.0.tar.gz` e `SHA256SUMS` dalla release,
`sha256sum -c SHA256SUMS`, estrarre e lanciare `sudo ./bootstrap.sh --admin "$USER" [--check]`.

Poi, in un **nuovo** terminale: `claude` → completare il login personale → un prompt all'agente (per esempio
"completa la configurazione iniziale"). L'agente parte in `/srv/ops`, trova `docs/bootstrap/avanzamento.md` con
`STATO: IN CORSO`, rileva i parametri, chiede **una sola volta** i dati mancanti, compila `host.conf` e indica il
comando unico. Il proprietario lo lancia da una sessione SSH:

```bash
sudo ops-installa      # una password; rilanciare lo stesso comando dopo una sosta o un errore
```

`ops-installa` (installato da `bootstrap.sh` in `/usr/local/sbin`, root) mostra piano ed esclusioni, chiede `SI`
una volta ed esegue i passi 1–12 con gli script del pacchetto, verificati per impronta: dry-run, esecuzione, VERIFY,
arresto al primo errore, ripresa dal primo passo non superato. Si ferma per una persona solo per il nuovo login SSH
dopo l'attivazione del firewall, per il riavvio presidiato e per l'approvazione della finestra di manutenzione.
L'agente legge gli esiti in `/var/log/ops-installa/` senza sudo; nessun output da copiare in chat. Dettagli:
`docs/bootstrap/configurazione-server-base.md`, sezione "Esecuzione unica".

Sistemi: Ubuntu Server LTS; collaudo su macchina reale con **Ubuntu 26.04** (VM), prove automatiche in container
24.04 e 26.04. Su 26.04 il client NTP predefinito è chrony (accettato dalla checklist).

## Novità della 0.5.0 (comando unico e correzioni dal collaudo della 0.4.0, 2026-10-04)

| Correzione o novità | Dove |
|---|---|
| **Comando unico** `sudo ops-installa`: una autenticazione per esecuzione, parametri ed esclusioni dichiarati prima (`PROFILO`, `ESCLUSIONI` in `host.conf`, rispettate anche da `quick-check --gate`), dry-run → esecuzione → VERIFY per ogni passo, arresto al primo errore, ripresa senza ripetere i passi superati, log per comando in pseudo-terminale (`script -q -e`, nessuna pipe su apt/dpkg) leggibili dall'amministratore, avanzamento aggiornato con commit, `STATO: COMPLETATO` solo a passo 12 superato | `docs/bootstrap/ops-installa`, `bootstrap.sh` |
| Integrità: solo file del pacchetto con l'impronta registrata da `bootstrap.sh` in `/var/lib/ops-bootstrap` (root), eseguiti da una copia di root; correzioni locali solo con `--dichiara-correzione` e conferma scritta | `ops-installa` |
| Conferma del firewall dal nuovo login SSH rilevata nella stessa esecuzione (o rilanciando dal nuovo login), riavvio presidiato con ripresa dopo l'avvio, approvazione della finestra con conferma scritta | `ops-installa` |
| Rilevazione dei parametri senza sudo e richiesta unica dei dati mancanti | `docs/bootstrap/rileva-parametri.sh` |
| Verifiche in sola lettura delle voci senza script (1, 2, 4, 7.1, 10.3, 11, 12.4–12.7) | `docs/bootstrap/verifiche-base.sh` |
| Difetto 5: `passo7` usciva con 4 su 26.04 (`&& echo` come ultima istruzione di un ciclo in `$( … \| … )`) | `passo7-impostazioni.sh` |
| Difetto 7: 12.5 accetta `disabled (routed)` (macchina senza Docker) | `passo12-verifiche.sh` |
| Difetti 1–2: utente `sync` atteso; amministratore tolto anche da `lxd` | checklist 5, `docs/decisions.md`, nuovo `passo5-utenti.sh` |
| Difetti 4, 6, 8: sessioni SSH con `ss` (non `who`), niente `\| head` sotto `pipefail`, ora del ripristino UFW calcolata all'armamento | `passo6`, `passo7` |

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
| installa i file della manutenzione con `/srv/ops/maint/install-maint install` e il comando unico `/usr/local/sbin/ops-installa` con le impronte del pacchetto in `/var/lib/ops-bootstrap` | installare applicazioni, Docker, backup, agenti applicativi (Docker e backup li installa `ops-installa`, lanciato dal proprietario dopo la dichiarazione dei parametri) |

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
| `payload/ops/docs/bootstrap/ops-installa` | comando unico della configurazione iniziale (copia eseguita: `/usr/local/sbin/ops-installa`) |
| `payload/ops/docs/bootstrap/passo*.sh`, `verifiche-base.sh` | script dei passi della checklist (PRECHECK, BACKUP, MODIFICA, VERIFY, `--dry-run`, `--rollback`) e verifiche in sola lettura, eseguiti da `ops-installa` |
| `payload/ops/docs/bootstrap/rileva-parametri.sh` | proposta di `host.conf` e dati da chiedere al proprietario (senza sudo) |
| `payload/home/` | adattatori per la home dell'amministratore |
| `payload/ops/bin/kb`, `payload/ops/kb.conf.tmpl` | strumento e configurazione della Knowledge Base condivisa |
| `tests/kb-scenario.sh` | collaudo dello strumento kb con un repository remoto fittizio e due copie |
| `tests/` | collaudo in container (`run-container-test.sh`, `scenario.sh`, `installa-scenario.sh` per il comando unico) |

Differenze rispetto al server di origine (solo parametrizzazione): nomi fissi `ops-*` al posto di `servern100-*`,
parametri della macchina in `/srv/ops/host.conf` (utente) e `/etc/ops-maint.conf` (root, letto senza eseguirlo),
`install-maint` al posto di `maint/install.sh` (che non viene distribuito), Node.js 22 (minimo dichiarato da
Claude Code). Non distribuiti: dati, credenziali, memorie, cronologia, autorizzazioni operative del server di origine (la
finestra va approvata per ogni macchina), `sqlite-snapshots.sh` (file root del server di origine non ancora estratto e
verificato: va estratto con sudo, riletto e parametrizzato prima di includerlo).

## Collaudo

**Fatto — in container (0.5.0).** `tests/run-container-test.sh` (Docker, container usa e getta senza systemd;
`IMAGE=ubuntu:26.04` per la 26.04): **@@NTEST@@**. Oltre alle prove della 0.4.0 (distribuzione, idempotenza,
conflitti, Knowledge Base, `quick-check`, logrotate, lettore di `host.conf`, passi 3, 9, 10 parziali, shellcheck),
`tests/installa-scenario.sh` prova:
- installazione di `ops-installa` e delle impronte di root da parte di `bootstrap.sh`; `--piano` senza sudo con tutti i
  parametri mancanti in un solo elenco; rifiuto senza sudo; file del pacchetto modificato → nessun passo (anche se
  l'amministratore aggiorna il proprio manifest); radice di prova ignorata dalla copia installata;
- regressioni della consegna: difetto 5 riprodotto con la riga 0.4.0 e corretto, nessun ciclo a rischio negli script,
  12.5 con `disabled (routed)`, `ss` al posto di `who`, ora del ripristino, niente `| head` nel passo 7;
- passo 5 su gruppi reali (lxd, docker, adm; `sync` atteso; `NOPASSWD` → arresto; rollback);
- rilevazione dei parametri e `--scrivi` (mai sovrascrive); `quick-check` e `--gate` con `ESCLUSIONI`;
- flusso completo con gli script dei passi simulati: ordine e dry-run, sosta e conferma del firewall (nella stessa
  esecuzione o dal nuovo login), riavvio normale e con `ops-maint attended`, ripresa dopo l'avvio, approvazione della
  finestra, `STATO: COMPLETATO`, rilancio senza modifiche; arresto al primo errore con codice reale nel log e ripresa
  senza ripetere i passi superati; dry-run non superato; ripristino automatico del firewall scattato; `--rollback`;
  correzione locale dichiarata; parametri incompleti; orari vietati; piano non confermato; log leggibili e non
  modificabili dall'amministratore.
Gli script dei passi 6, 7, 8, 10, 10b e 12 richiedono systemd, APT e rete reali: in container solo controlli parziali.

**Fatto — VM di laboratorio, 0.4.0** (Ubuntu Server 26.04.1, Hyper-V, installazione da zero, 2026-10-04): passi 0–12
con gli script distribuiti, riavvio presidiato normale e controlli dopo l'avvio; difetti 1–8 della consegna (corretti
in 0.5.0). Esclusi: 7.1, 2, 10.3, 12.3, 11.2 (provato sulla prima VM), manutenzione automatica, `ops-postboot`,
`ops-maint attended`, 12.8. Esecuzione con 29 richieste di password e 8 script locali: il motivo della 0.5.0.
**Fatto — sul server di origine** (fisico, Ubuntu 24.04): scenario `kb` e prove sul repository GitHub reale (0.3.0).

**Da provare prima della pubblicazione: flusso unico della 0.5.0 su una VM pulita Ubuntu Server 26.04** (bootstrap da
`install.sh` o dall'archivio verificato, nessuna correzione manuale, nessuno script locale):
1. `bootstrap.sh` → `ops-installa` in `/usr/local/sbin` e impronte in `/var/lib/ops-bootstrap`;
2. agente: `rileva-parametri.sh`, una sola richiesta, `host.conf` con commit, `ops-installa --piano` pulito;
3. `sudo ops-installa` da SSH: **una** password fino alla conferma del firewall nella stessa esecuzione (difetto 5
   corretto: passo 7 con esito 0 su 26.04), riavvio con `RIAVVIA`, poi **una** password dopo l'avvio fino a
   `STATO: COMPLETATO`; contare le richieste di password (atteso: 1 per bootstrap + 1 per esecuzione);
4. ripresa: interrompere una volta (es. `dopo` alla conferma SSH, o un passo fatto fallire) e rilanciare;
5. log: l'agente legge esiti e codici in `/var/log/ops-installa/` senza sudo; nessuna sospensione di apt (stato `T`);
   eventuali richieste di debconf o needrestart nello pseudo-terminale (non osservate sulla VM, da registrare);
6. profilo `docker` (passo 8) e, se possibile, `base` (12.5 con `disabled (routed)`);
7. `--rollback 7` e `--dichiara-correzione` almeno una volta.

**Per la produzione servono inoltre:** rete stabile (7.1), volumi dedicati (2), copia remota con ripristino provato
(10.3, 12.2 da remoto, 12.3), Healthchecks sulla 0.5.0 (11.2), `ops-maint attended` con `ops-postboot` e attivazione
con prima esecuzione dei timer (12.8), `install.sh` dalla release pubblicata.
