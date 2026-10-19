> Candidato **0.8.0-rc.1**, base v0.7.0 congelata. Pre-release sperimentale: collaudo VM ancora da eseguire.
> Per questa revisione seguire [COLLAUDO-VM-0.8.0.md](COLLAUDO-VM-0.8.0.md).
> I comandi pubblici 0.7.0 sotto restano riferiti alla release stabile precedente.

# setup-server-linux

Prepara un **Ubuntu Server LTS appena installato** per l'amministrazione con agenti, applicando la base collaudata
sul server di origine: regole (`AGENTS.md`), documenti, checklist, script di controllo, manutenzione e monitoraggio.
Versione: vedi `VERSION`.

> **Stato: pre-release, non pronta per la produzione.** La 0.4.0 è stata collaudata su una VM pulita con
> **Ubuntu Server 26.04.1 LTS** (Hyper-V), con esito "collaudo locale completato con esclusioni", ma con 29 richieste
> di password e 8 script locali. La 0.5.0 ha introdotto il **comando unico** `sudo ops-installa`, collaudato su una
> VM 26.04.1 da zero con esito "collaudo locale completato con esclusioni (7.1 10.3 11.2 12.8); validazione per
> produzione incompleta" e un difetto (D1). La 0.5.1 corregge D1; la 0.6.0 rende la Knowledge Base facoltativa, con
> repository scelto dall'utente e lettura via HTTPS. La 0.7.0 installa sempre quattro agenti di amministrazione con
> sandbox (Claude Code, Codex CLI, Antigravity CLI, Gemini CLI) e fa scegliere quello della sessione; integra le
> correzioni del collaudo 0.6.0. Gemini usa ora la sandbox nativa degli strumenti: sulla VM Ubuntu 26.04.1
> legge il server e protegge la home (11 ottobre, Gemini 0.63.0, nessuna chiamata al modello).
> Correzione Gemini dell'11 ottobre: 313/313 su Ubuntu 24.04 e 26.04 dal commit fisso `34b6f1f`.
> Login reale e flusso della VM ancora da completare; dettagli in `payload/ops/docs/bootstrap/gemini-collaudo-2026-10-11.md`.
> Prove ancora mancanti: sezione "Collaudo".

## Installazione (release identificata, integrità verificata)

Sulla macchina nuova, come **utente amministratore normale** creato dall'installer di Ubuntu (nel gruppo `sudo`,
non root), con l'impronta SHA-256 riportata nella pagina della release:

```bash
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.7.0/install.sh \
  | bash -s -- --sha256 <IMPRONTA> --check   # solo controllo: piano e conflitti, nessuna modifica
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.7.0/install.sh \
  | bash -s -- --sha256 <IMPRONTA>           # esecuzione (ripetibile)
```

`install.sh` rifiuta root, scarica l'archivio della release `v0.7.0`, lo confronta con `SHA256SUMS` della release e
con l'impronta passata a `--sha256`, lo estrae in `~/setup-server-linux-0.7.0` e avvia
`sudo bootstrap.sh --admin <utente>` (sudo chiede la password). Gli agenti e i loro login restano nell'account
dell'amministratore (Antigravity: programma di root in `/opt/ops-agenti`). Opzioni: `--owner "Nome"` (nome del
proprietario usato nelle regole; di default il primo nome del campo GECOS), `--agente claude|codex|agy|gemini` (agente
della sessione senza domanda finale).

Alternativa manuale: scaricare `setup-server-linux-0.7.0.tar.gz` e `SHA256SUMS` dalla release,
`sha256sum -c SHA256SUMS`, estrarre e lanciare `sudo ./bootstrap.sh --admin "$USER" [--check]`.

Alla fine il bootstrap chiede **"Con quale agente vuoi avviare la sessione? Claude Code / Codex CLI / Antigravity CLI /
Gemini CLI"**. Poi `/srv/ops/bin/agente` (nei nuovi terminali: `agente`) guida il login personale **solo** di
quell'agente (URL da aprire nel browser del PC), lo collauda e lo avvia in `/srv/ops`; un prompt all'agente (per esempio
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

## Novità della 0.7.0 (agenti di amministrazione e correzioni del collaudo 0.6.0, 2026-10-06)

| Novità o correzione | Dove |
|---|---|
| **Quattro agenti sempre installati**, ciascuno con programma reale, dipendenze, sandbox e permessi: Claude Code (npm, bubblewrap + socat), Codex CLI (npm, bubblewrap, config e regole), **Antigravity CLI** (Google, account personale gratuito; binario ufficiale con SHA-512 in `/opt/ops-agenti`, di root, profilo AppArmor mirato `ops-agy`, aggiornamenti da root con `ops-agy`), Gemini CLI (Google, chiave API; sandbox nativa degli strumenti con bubblewrap e seccomp) | `bootstrap.sh`, `maint/ops-agy`, `payload/home/*` |
| Domanda finale "Con quale agente vuoi avviare la sessione?" (`AGENTE` in `host.conf`) e comando unico **`agente`** per cambiarlo in seguito, senza reinstallare e senza toccare l'avanzamento: login guidato del solo agente scelto, collaudo operativo, avvio in `/srv/ops`, scelta di un altro agente se quello scelto non è utilizzabile | `bin/agente`, `bootstrap.sh` |
| `cli-update`: ambiente e sandbox dei quattro senza login (`--ambiente`), collaudo operativo del solo agente della sessione (`--verify`: login, `AGENTS.md` con uscita 0, prova di isolamento); un agente non autenticato, senza abbonamento o con quota esaurita non blocca. Integra la correzione locale della VM (commit `96f2579`): `host.conf` letto senza eseguirlo, dichiarazioni doppie respinte, uscita non zero = fallimento; `AGENTI_CLI="codex"` della VM resta accettato | `bin/cli-update` |
| Codex: bubblewrap tra i prerequisiti, `workspace-write` + `on-request`, regole `allow` per i comandi ordinari (eseguiti fuori dalla sandbox senza richiesta), `sudo` vietato; nessun `danger-full-access` | `codex-config.toml`, `codex-ops.rules` |
| `kb sync` distingue la rete chiusa della sandbox di Codex ("limite della sandbox, non un guasto") da un guasto reale; il successo è solo la riga "sincronizzata:" | `bin/kb` |
| `quick-check`: per ogni agente conta solo l'ultimo esito (il vecchio fallimento di Claude non resta segnalato); login mancante solo per l'agente della sessione | `bin/quick-check` |
| Profilo `ops-bwrap` solo dove Ubuntu non ha un profilo per `/usr/bin/bwrap` (24.04) e la restrizione dei namespace è attiva | `bootstrap.sh`, `ops-agy profilo bwrap` |
| Blocco `~/.bash_aliases` delle versioni 0.1.0–0.6.0 aggiornato senza conflitto (funzioni `agente`, `agy` da `/opt`) | `bootstrap.sh` |

## Novità della 0.6.0 (Knowledge Base facoltativa via HTTPS, 2026-10-05)

| Novità | Dove |
|---|---|
| Nessun repository KB predefinito; domanda "Vuoi collegare una Knowledge Base? [S/N]" durante l'avvio, URL HTTPS, prova senza credenziali, token di sola lettura con input nascosto solo se serve; correzione, riprova o rinuncia senza reinstallare la foundation; scelta registrata (nessuna domanda ripetuta) | `bootstrap.sh`, `bin/kb` (`kb collega`), `kb.conf` |
| Token fuori dai repository (0700/0600), consegnato a git solo dall'helper `kb credenziale`; escluso dai backup; `kb token` per sostituirlo; token scaduto o revocato = copia conservata e "ACCESSO NEGATO" senza interrompere la gestione | `bin/kb`, modello di borgmatic |
| Lettura via HTTPS e pubblicazione separate: `kb publish` rifiutato sui server HTTPS; deploy key e SSH delle installazioni esistenti invariati | `bin/kb`, `bootstrap.sh` |
| `--no-kb`, `--kb-url` in `bootstrap.sh` e `install.sh`; guida al token | `install.sh`, `docs/runbooks/knowledge-base.md`, `AGENTS.md` |

## Novità della 0.5.1 (correzione D1 dal collaudo della 0.5.0, 2026-10-04)

| Correzione | Dove |
|---|---|
| D1: `ops-installa` esegue gli script da una copia di root con file 0600; il passo 9 lanciava direttamente `"$MAINT_SRC/install-maint" status` → `Permission denied`, codice 126 dopo MODIFICA e VERIFY superati. Ora `bash "$MAINT_SRC/install-maint" status`; regola scritta accanto al `chmod 0600` | `passo9-manutenzione.sh`, `ops-installa` |
| Test di regressione: controllo statico (nessun file della copia protetta eseguito direttamente) e passo 9 **reale** eseguito da `ops-installa` dalla copia 0600 (forma 0.5.0: codice 126; forma corretta: esito 0 e ripresa dal passo 9) | `tests/installa-scenario.sh` (T24) |

## Novità della 0.5.0 (comando unico e correzioni dal collaudo della 0.4.0, 2026-10-04)

| Correzione o novità | Dove |
|---|---|
| **Comando unico** `sudo ops-installa`: una autenticazione per esecuzione, parametri ed esclusioni dichiarati prima (`PROFILO`, `ESCLUSIONI` in `host.conf`; un'esclusione chiude solo il collaudo locale, `STATO: COMPLETATO CON ESCLUSIONI`; la copia remota esclusa continua a bloccare `quick-check --gate`, `ops-maint attended` e la finestra), dry-run → esecuzione → VERIFY per ogni passo, arresto al primo errore, ripresa senza ripetere i passi superati, log per comando in pseudo-terminale (`script -q -e`, nessuna pipe su apt/dpkg) leggibili dall'amministratore, avanzamento aggiornato con commit, `STATO: COMPLETATO` solo a passo 12 superato | `docs/bootstrap/ops-installa`, `bootstrap.sh` |
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

## Knowledge Base (facoltativa)

Una Knowledge Base tecnica, cioè un **repository Git separato scelto dall'utente** (nessun repository predefinito), può
essere collegata alla foundation: copia locale in `/srv/ops/knowledge-base`, gestita da `/srv/ops/bin/kb`, regole per
gli amministratori in `AGENTS.md` (SYNC BEFORE WORK, KNOWLEDGE FIRST, LEARN & CONSOLIDATE, VERIFY BEFORE PUBLISH, APPEND
ONLY). Senza KB la foundation funziona normalmente.

**Durante l'avvio** il bootstrap chiede `Vuoi collegare una Knowledge Base? [S/N]`:
- **N**: "KB non configurata per scelta" (registrato in `kb.conf`; la domanda non viene ripetuta);
- **S**: URL HTTPS del repository. Prima prova **senza credenziali** (repository pubblico); se serve autenticazione
  chiede un **token di sola lettura** con input nascosto (mai la password dell'account). Se l'accesso non riesce:
  correggere l'URL, reinserire il token, riprovare o continuare senza KB, senza reinstallare la foundation. Con
  l'accesso verificato scarica la copia e attiva la sincronizzazione ogni 6 ore.
- Opzioni non interattive: `--no-kb`, `--kb-url https://…` (anche da `install.sh`). Più tardi, senza sudo:
  `/srv/ops/bin/kb collega`.

**Token** (GitHub: *fine-grained personal access token* limitato al solo repository della KB, **Contents:
Read-only**, più Metadata read-only aggiunto da GitHub): si crea una volta, si conserva nel gestore di password e si
incolla sui server. Sul server sta in `~/.config/ops-kb/token` dell'amministratore (cartella 0700, file 0600), fuori dai
repository e dai backup; git lo riceve solo dall'helper `kb credenziale`, mai da URL, argomenti, log, crontab o commit.
Scaduto o revocato: `kb sync` lo segnala ("ACCESSO NEGATO"), conserva la copia locale ed esce con 0; si sostituisce con
`kb token`, che verifica il nuovo accesso prima di salvarlo. Lo stesso token su più macchine va sostituito su tutte.
Guida: `docs/runbooks/knowledge-base.md`.

| Comando | Effetto |
|---|---|
| `kb collega`, `kb token` | collegamento facoltativo via HTTPS; sostituzione del token di lettura |
| `kb sync` | recupera i record; non tocca il lavoro locale; senza rete o con accesso negato usa la copia locale (e lo dichiara); mai modifiche ai programmi installati, mai esecuzione di script della KB |
| `kb new "Titolo"` → `kb validate` → `kb publish` | nuovo record APPEND ONLY; la **pubblicazione** è riservata ai server con scrittura autorizzata (collegamento SSH): un server collegato via HTTPS legge soltanto |
| `kb status`, `kb index`, `kb search` | stato della copia (con l'ultimo errore di accesso), indice locale dei record, ricerca |
| `kb schedule on` | sincronizzazione leggera ogni 6 ore (crontab dell'amministratore) |

**Compatibilità.** Le installazioni precedenti con deploy key continuano a funzionare com'erano; `--kb-remote` con un
URL SSH o un percorso locale usa ancora quel collegamento. `--knowledge-base-only` aggiorna solo strumento,
configurazione e copia della KB (e ripropone il collegamento se era stato rifiutato). Una copia incorporata della 0.2.0
viene spostata in `knowledge-base.v0.2.0-<data>` (conservata).

Il pacchetto ricrea la **foundation e la sua conoscenza**, non le applicazioni: nessuna installazione automatica di
ciò che la Knowledge Base descrive.

## Requisito Node.js

Node.js **22** da NodeSource (`node_22.x`, chiave verificata per impronta), perché il pacchetto npm di Claude Code
lo richiede: `npm view @anthropic-ai/claude-code@stable version engines` → `2.1.274`,
`engines: { node: '>=22.0.0' }` (metadati del registro npm consultati il 2026-09-27). Ubuntu 24.04 fornisce Node.js 18.

## Cosa fa (e cosa no)

| Fa | Non fa |
|---|---|
| installa `git curl ca-certificates gnupg jq`, i componenti delle sandbox (`bubblewrap socat apparmor`) e Node.js 22 da NodeSource (chiave verificata per impronta) | partizionare, formattare, montare dischi |
| crea `/srv/ops` (repository Git) con regole, adattatori, documenti, checklist, script, `host.conf` | toccare rete, SSH, firewall, gruppi o privilegi degli utenti, hostname |
| installa i quattro agenti (Claude Code, Codex CLI, Gemini CLI con npm per l'amministratore; Antigravity CLI da root in `/opt/ops-agenti`), autoaggiornamento disattivato, sandbox e permessi configurati; profili AppArmor mirati `ops-agy` e, solo dove manca quello di Ubuntu, `ops-bwrap` | attivare timer o servizi: tutte le unit `ops-*` restano disabilitate; attivare servizi a pagamento; disattivare restrizioni globali di Ubuntu |
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
| `tests/` | collaudo in container (`run-container-test.sh`, `scenario.sh`, `installa-scenario.sh` per il comando unico, `kb-https-scenario.sh` e `kb-https-server.py` per la KB via HTTPS, simulata) |

Differenze rispetto al server di origine (solo parametrizzazione): nomi fissi `ops-*` al posto di `servern100-*`,
parametri della macchina in `/srv/ops/host.conf` (utente) e `/etc/ops-maint.conf` (root, letto senza eseguirlo),
`install-maint` al posto di `maint/install.sh` (che non viene distribuito), Node.js 22 (minimo dichiarato da
Claude Code). Non distribuiti: dati, credenziali, memorie, cronologia, autorizzazioni operative del server di origine (la
finestra va approvata per ogni macchina), `sqlite-snapshots.sh` (file root del server di origine non ancora estratto e
verificato: va estratto con sudo, riletto e parametrizzato prima di includerlo).

## Collaudo

**0.7.0 — esito delle prove (2026-10-06): 311/311 su `ubuntu:24.04` e `ubuntu:26.04`** (`tests/agenti-scenario.sh` più le
prove delle versioni precedenti). Distinzione:
- **Prove simulate** (CLI finti, nessun modello contattato): agente della sessione e compatibilità `AGENTI_CLI`; altri
  agenti senza login che non bloccano; uscita non zero con testo atteso (consegna 0.6.0); quota esaurita; login
  mancante; isolamento violato (ripiego fuori dalla sandbox) e "NON DIMOSTRATO"; ambiente non conforme per bubblewrap,
  sandbox di Codex e Gemini nativo, impostazioni di Claude, Antigravity e Gemini CLI; esecuzione con ambiente vuoto (timer);
  aggiornamento (Antigravity mai da `cli-update`); `quick-check` sull'ultimo esito; comando `agente` (domanda, login del
  solo agente scelto, collaudo, commit, avvio, ripiego su un altro, input terminato); `kb sync` nella sandbox di Codex;
  `ops-installa --piano` con `AGENTE`.
- **Prove reali in container** (pacchetti, npm e download veri; nessun login; Docker non permette namespace): i quattro
  agenti installati ed eseguibili senza shell interattiva; Antigravity 1.3.0 dal manifest ufficiale con SHA-512 in
  `/opt/ops-agenti` (`root:root 755`, non scrivibile dall'amministratore, nessuna modifica a PATH e profili);
  componenti delle sandbox; configurazioni dei quattro; regole di Codex con `codex execpolicy check`
  reale; profili `ops-agy` e `ops-bwrap` accettati da `apparmor_parser`; blocco `.bash_aliases` della 0.6.0 aggiornato;
  domanda finale con risposta non valida e valida. In container bubblewrap **non** crea namespace:
  "AMBIENTE NON CONFORME" atteso.
- **Prove reali sul server di origine** (senza modifiche ad AppArmor): restrizione dei namespace attiva; Codex senza
  bubblewrap di Ubuntu non avvia la sandbox; Antigravity 1.2.16 senza profilo non avvia la sandbox
  (`sbox: bringLoopbackUp: … operation not permitted`) e ripiega fuori; regole di Codex con `codex execpolicy`.
- **Non provato** (prossima VM): sandbox di Antigravity con `ops-agy`, flusso `agente` con login reale da SSH,
  `ops-bwrap` su 24.04 reale, login e collaudo completo di Gemini CLI con chiave vera, `ops-agy update`/`rollback` reali, successo della
  sincronizzazione KB dal cron (visto partire, successo non dimostrato).

**Fatto — in container (0.6.0).** `tests/run-container-test.sh` (Docker, container usa e getta senza systemd;
`IMAGE=ubuntu:26.04` per la 26.04): **241/241 prove superate sia su `ubuntu:24.04` sia su `ubuntu:26.04`** (0.5.1: 203/203). `tests/kb-https-scenario.sh` (prove SIMULATE: server
Git HTTPS locale con certificato di prova, token fittizi, nessun accesso a GitHub): nessuna KB (N, `--no-kb`, nessun
terminale), repository pubblico, privato con token, token errato con reinserimento, URL errato con correzione, URL con
credenziali rifiutato, riprova e rinuncia, sincronizzazione successiva senza terminale, token revocato (copia
conservata, esito 0), sostituzione con `kb token` (anche errata), `kb publish` rifiutato via HTTPS, helper che non
risponde ad altri host, token assente da configurazioni, log, URL, crontab, commit e argomenti dei processi
(`GIT_TRACE`), bootstrap con le domande all'avvio e senza ripetizioni. Oltre alle prove della 0.4.0 (distribuzione, idempotenza,
conflitti, Knowledge Base, `quick-check`, logrotate, lettore di `host.conf`, passi 3, 9, 10 parziali, shellcheck),
`tests/installa-scenario.sh` prova:
- installazione di `ops-installa` e delle impronte di root da parte di `bootstrap.sh`; `--piano` senza sudo con tutti i
  parametri mancanti in un solo elenco; rifiuto senza sudo; file del pacchetto modificato → nessun passo (anche se
  l'amministratore aggiorna il proprio manifest); radice di prova ignorata dalla copia installata;
- regressioni della consegna: difetto 5 riprodotto con la riga 0.4.0 e corretto, nessun ciclo a rischio negli script,
  12.5 con `disabled (routed)`, `ss` al posto di `who`, ora del ripristino, niente `| head` nel passo 7;
- passo 5 su gruppi reali (lxd, docker, adm; `sync` atteso; `NOPASSWD` → arresto; rollback);
- rilevazione dei parametri e `--scrivi` (mai sovrascrive);
- esclusioni e manutenzione: con 10.3 esclusa la copia remota mancante resta un'attenzione, `quick-check --gate` esce
  con 1 e `ops-maint window` (stesso controllo di `attended` e della finestra; `DRY_RUN` con riavvio richiesto)
  **rinvia**; controprova: con la copia remota eseguita lo stesso `ops-maint` arriva al riavvio. La verifica 11.1
  accetta il gate bloccato solo dalla copia remota (collaudo locale), mai con altri problemi; 10.3 esclusa senza 12.8
  è rifiutata; con esclusioni l'esito è `STATO: COMPLETATO CON ESCLUSIONI` (validazione per produzione incompleta),
  senza esclusioni `STATO: COMPLETATO`;
- flusso completo con gli script dei passi simulati: ordine e dry-run, sosta e conferma del firewall (nella stessa
  esecuzione o dal nuovo login), riavvio normale e con `ops-maint attended`, ripresa dopo l'avvio, approvazione della
  finestra, `STATO: COMPLETATO`, rilancio senza modifiche; arresto al primo errore con codice reale nel log e ripresa
  senza ripetere i passi superati; dry-run non superato; ripristino automatico del firewall scattato; `--rollback`;
  correzione locale dichiarata; parametri incompleti; orari vietati; piano non confermato; log leggibili e non
  modificabili dall'amministratore.
Gli script dei passi 6, 7, 8, 10, 10b e 12 richiedono systemd, APT e rete reali: in container solo controlli parziali.

**Fatto — VM di laboratorio, 0.5.0** (Ubuntu Server 26.04.1, Hyper-V Default Switch con DHCP, disco unico, profilo
`docker` senza container, esclusioni 7.1 10.3 11.2 12.8; 2026-10-04, riferito dall'agente della VM): `sudo ops-installa`
in 4 esecuzioni con esito "collaudo locale completato con esclusioni; validazione per produzione incompleta".
Superati: guardia del terminale (piano non confermato senza terminale vero), passi 1–8 al primo tentativo, sosta del
passo 7 con conferma da un nuovo login SSH, ripresa dal passo 9 dopo l'errore D1 (con `--dichiara-correzione`) senza
ripetere 1–8, passi 9, 10, 10b, 11.1 (gate bloccato solo dalla copia remota esclusa), 12, riavvio da `ops-installa` e
ripresa dopo l'avvio (12.4), 12.6, 12.7. Dopo il collaudo: unit di manutenzione disabilitate, `APPROVED=no`.
Esito registrato anche nella Knowledge Base condivisa (privata).

**Fatto — VM di laboratorio, 0.4.0** (2026-10-04): passi 0–12 con 29 richieste di password e 8 script locali; difetti
1–8 corretti in 0.5.0.
**Fatto — sul server di origine** (fisico, Ubuntu 24.04): scenario `kb` e prove sul repository GitHub reale (0.3.0).

**Non ancora provato su una macchina reale:** collegamento della KB 0.6.0 a GitHub reale (repository pubblico e privato
con un fine-grained token vero), scadenza o revoca reale del token, sincronizzazione dal cron; inoltre (0.5.x):
1. la 0.5.1/0.6.0 su una VM (D1 corretto: passo 9 al primo tentativo);
2. installazione dal percorso pubblico `install.sh` sulla VM (provato solo `--check` in container);
3. interruzione volontaria di `ops-installa` durante un passo (Ctrl-C, chiusura di SSH) e ripresa;
4. rollback reali: ripristino automatico di UFW scattato, `--rollback` di un passo, rollback di `/etc/ops-maint.conf`;
5. rami di rifiuto di `--dichiara-correzione`; riavvio non avvenuto o controlli dopo l'avvio non superati;
6. profilo `base` (12.5 con `disabled (routed)`); conteggio delle password sul percorso completo;
7. richieste interattive di debconf o needrestart nello pseudo-terminale (non osservate).

**Per la produzione servono inoltre:** rete stabile (7.1), volumi dedicati (2), copia remota con ripristino provato
(10.3, 12.2 da remoto, 12.3), Healthchecks (11.2), `ops-maint attended` con `ops-postboot`, attivazione e prima
esecuzione della finestra e del timer `ops-cli-update` (12.8): tutte escluse nel collaudo della 0.5.0.


## Chiusura del collaudo locale (11 ottobre 2026)
Antigravity operativo sulla VM Ubuntu 26.04: workspace scrivibile, home protetta, ripresa dopo riavvio riuscita. Correzioni del profilo bwrap, delle regole Antigravity e del timeout integrate. Gemini usa sandbox nativa dei tool; login API non collaudato. Guida unica: payload/ops/docs/bootstrap/guida-installazione-0.7.0.md. Rapporto e limiti: payload/ops/docs/bootstrap/chiusura-0.7.0.md. Validazione produzione incompleta; questa release resta pre-release.

## Flusso deterministico comune (12 ottobre 2026)
Il collaudo su VM pulita ha mostrato che il prompt AI iniziale chiedeva approvazioni ordinarie ripetute. Il requisito non era soddisfatto. Ora installa-server.sh e install.sh --configura avviano configura-server nel terminale reale: rilevamento, parametri, piano, login del solo agente, sudo ops-installa e rapporto. La chat non esegue i passi. L'impronta dei parametri lega il piano dichiarato all'esecuzione; file del pacchetto e stato restano protetti da root. Le prove precedenti 315/315 non validano questa modifica; banco mirato e regressioni complete sono separati dal collaudo VM. Dettagli: payload/ops/docs/bootstrap/flusso-deterministico.md.
# Correzioni di collaudo del 13 ottobre 2026 (non una nuova release)

La configurazione deterministica compila la memoria iniziale della macchina dopo i passi superati,
preserva i testi personalizzati e registra le esclusioni. Il rapporto finale usa `kb sync --quiet --strict`:
un collegamento non aggiornabile non vale come sincronizzazione riuscita. Il cron e il comando ordinario
mantengono l'uso della copia locale quando la rete non risponde.

Il controllo Claude esegue anche il helper incorporato `apply-seccomp`, senza login o modello, e verifica
workspace, home protetta, capacità effettive/permesse rimosse, NoNewPrivs e seccomp. Il solo avvio di
bubblewrap non basta. Il bootstrap installa l’adattatore root-owned e il profilo AppArmor dedicato di Claude,
senza modificare i sysctl o il profilo bubblewrap di Ubuntu. L’avvio normale, il controllo rapido e il resoconto
KB sono riusciti sulla VM Ubuntu 26.04 con Claude autenticato. Il comando agente riprende le verifiche dopo
il riavvio PRIMA del login nel flusso differito. L’installazione completa del candidato su VM pulita resta distinta.

Prove mirate: `tests/memoria-iniziale-test.py`, `tests/configura-server-scenario.sh`,
`tests/claude-sandbox-check-scenario.sh`, `tests/kb-strict-scenario.sh`. Le prove con processi finti
non certificano le sandbox del kernel né gli account reali; il test Git locale non certifica il cron
o l'accesso alla KB privata su GitHub.
