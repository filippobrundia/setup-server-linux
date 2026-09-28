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
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.3.0/install.sh \
  | bash -s -- --sha256 <IMPRONTA> --check   # solo controllo: piano e conflitti, nessuna modifica
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.3.0/install.sh \
  | bash -s -- --sha256 <IMPRONTA>           # esecuzione (ripetibile)
```

`install.sh` rifiuta root, scarica l'archivio della release `v0.3.0`, lo confronta con `SHA256SUMS` della release e
con l'impronta passata a `--sha256`, lo estrae in `~/setup-server-linux-0.3.0` e avvia
`sudo bootstrap.sh --admin <utente>` (sudo chiede la password). Claude Code e il suo login restano nell'account
dell'amministratore. Opzione: `--owner "Nome"` (nome del proprietario usato nelle regole; di default il primo nome
del campo GECOS).

Alternativa manuale: scaricare `setup-server-linux-0.3.0.tar.gz` e `SHA256SUMS` dalla release,
`sha256sum -c SHA256SUMS`, estrarre e lanciare `sudo ./bootstrap.sh --admin "$USER" [--check]`.

Poi, in un **nuovo** terminale: `claude` → completare il login personale. L'agente parte in `/srv/ops`, trova
`docs/bootstrap/avanzamento.md` con `STATO: IN CORSO` e prosegue con la checklist secondo `AGENTS.md`.

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

**Fatto — in container.** `tests/run-container-test.sh` (Docker, `ubuntu:24.04` usa e getta, senza systemd):
**72/72 prove superate** con la versione 0.3.0, comprese quelle della Knowledge Base condivisa (su un repository remoto
fittizio): primo recupero dal bootstrap, sincronizzazione ripetuta senza modifiche, regole in `AGENTS.md`, esito 4 e
messaggio esplicito senza accesso al repository, migrazione di una copia 0.2.0, nessun passo operativo con
`--knowledge-base-only`, e lo scenario `tests/kb-scenario.sh` (34/34: due copie indipendenti, pubblicazione e recupero,
pubblicazioni concorrenti con push respinto e ritentato, rifiuto di modifiche, cancellazioni e push forzati, esclusione
di chiavi, token, indirizzi privati ed email, record correttivi, funzionamento senza rete).
**Fatto — sul server di origine** (fisico, Ubuntu 24.04): stesso scenario `kb` (34/34, repository locale) e prove sul
repository GitHub reale con deploy key, due copie temporanee e record fittizi su un ramo di collaudo poi rimosso
(pubblicazione concorrente con respingimento e nuovo tentativo, recupero reciproco, modifica, cancellazione e force push
respinti). `install.sh` non è stato eseguito in container.

**Da provare su una VM o macchina Ubuntu Server pulita, con systemd, prima dell'uso in produzione:**
1. `bootstrap.sh` su Ubuntu Server reale (pacchetti di `ubuntu-server` già presenti, `unattended-upgrades` attivo
   al primo avvio: attesa dei blocchi APT);
2. `install-maint install` con systemd: `daemon-reload`, tmpfiles, nessuna unit abilitata;
3. login di Claude Code e primo avvio dell'agente: riconoscimento della configurazione incompleta;
4. `install-maint enable postboot|window|cli-update` con i prerequisiti, `cli-update --verify` dopo il login;
5. riavvio presidiato (`ops-maint attended`) e `ops-postboot`;
6. `bin/healthchecks setup` e prova dell'allarme con un controllo reale.
