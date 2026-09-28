# Paperclip in Docker con agenti isolati — conoscenza verificata

**Stato:** verificato su un'installazione reale (2026-09) — **Ultima verifica:** 2026-09-28.
Pagina trasferibile: vale per qualunque server Ubuntu con Docker. Runner in dettaglio: [runner-ssh.md](runner-ssh.md);
artefatti collaudati: [riferimento/](riferimento/README.md); test: [test/](test/README.md); prove e fallimenti:
[esperimenti](../../esperimenti/2026-09-paperclip-isolamento-agenti.md).

## Versioni a cui si applica

| Componente | Versione verificata | Dove è fissata |
|---|---|---|
| Paperclip | `v2026.916.1` (commit `d554c47`), immagine `ghcr.io/paperclipai/paperclip:2026.916.1@sha256:a02ac35a…` | Compose del progetto |
| PostgreSQL | 17.11, `postgres:17-alpine@sha256:b0f9560a…` | Compose del progetto |
| Codex CLI nel runner | 0.155.1 (la stessa inclusa nell'immagine Paperclip) | [riferimento/runner/Dockerfile](riferimento/runner/Dockerfile) (`CODEX_VERSION`) |
| Base di runner e proxy | `node:24-trixie-slim@sha256:8ec5d755…` (OpenSSH 10.0p2) | Dockerfile |
| Host | Ubuntu 24.04, Docker 29.8.1, Compose v5.5.1, `kernel.apparmor_restrict_unprivileged_userns=1` (default di Ubuntu) | — |

Ogni soluzione sotto vale per queste versioni. Con versioni diverse: rieseguire i test di regressione (fondo pagina).

## Prerequisiti

- Docker e Compose; una sola directory di progetto (per esempio `/srv/<progetto>`, creata una volta con sudo e poi
  di proprietà dell'amministratore, uid 1000); circa 3 GB per le immagini.
- Nessuna installazione applicativa sull'host: tutto in container. Accesso all'interfaccia solo con tunnel SSH verso
  `127.0.0.1:3100`.
- Account OpenAI con abbonamento (login di Codex fatto nell'interfaccia di Paperclip).

## Configurazione corretta fin dall'inizio

1. **Paperclip**: immagine ufficiale fissata per digest; `user: 1000:1000`, `cap_drop: ALL`, `no-new-privileges`
   (verificato funzionante: il passaggio root→`gosu` dell'immagine non serve); porta solo `127.0.0.1:3100`; modalità
   `authenticated` + `private`; limiti 4 GiB / 2 CPU / 2048 processi.
2. **Quattro segreti** passati come *secrets* di Compose (file) ed esportati solo dentro il processo da un
   `entrypoint` minimo: `DATABASE_URL` (password), `BETTER_AUTH_SECRET`, `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET`
   (richiesto dalla versione per le approvazioni firmate), `PAPERCLIP_AGENT_JWT_SECRET` (senza, il server usa
   `BETTER_AUTH_SECRET` anche per i token degli agenti; il banner deve dire "Agent JWT set"). Paperclip non supporta
   varianti `_FILE`: come variabili nel Compose sarebbero leggibili con `docker inspect`.
3. **PostgreSQL** in un container separato, su rete interna; dati in `data/postgres`; servono le capability
   `CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID` (tutte le altre tolte).
4. **Primo amministratore**: dal browser, registrazione e poi "Claim this instance" (modalità privata).
5. **Approvazione obbligatoria delle assunzioni** (`require_board_approval_for_new_agents = true`) subito dopo aver
   creato gli agenti iniziali. Effetto verificato: la creazione diretta di agenti viene rifiutata (409) **anche al
   board**; da lì in poi si assume solo con il flusso di approvazione.
6. **Agenti mai in esecuzione locale** nel container di Paperclip: ogni agente usa un **ambiente SSH** verso un
   runner dedicato. Per `codex_local` su SSH servono `engine: "cli"` (il motore ACP predefinito supporta solo le
   sandbox) e `maxConcurrentRuns: 1`; heartbeat a timer spenti; `canCreateSkills: false` finché la Skill Factory non è
   operativa; nessun segreto aggiuntivo nell'agente.
7. **Runner** ([riferimento/runner/](riferimento/runner/)): un container per **un solo agente**; utente 1001; root in sola lettura;
   `/work`, `/tmp`, home in RAM; sshd non root sulla porta interna 2222 con `ForceCommand` di sessione
   (`runner-session`) e pulitore (`runner-janitor`); chiave host in un volume montato **in sola lettura** (generata da
   una volta con un container usa e getta); documentazione per l'agente montata in sola lettura; nessun socket Docker, nessuna
   porta, nessun segreto di Paperclip; limiti 2 GiB / 1,5 CPU / 512 processi.
8. **Rete**: runner **solo su reti interne** (`aic-runner` con Paperclip, `aic-egress-int` con il proxy); unica uscita
   il container `egress-proxy` ([riferimento/egress-proxy/](riferimento/egress-proxy/)): solo `CONNECT` sulla 443 verso `api.openai.com`,
   `chatgpt.com`, `auth.openai.com`; mai IP diretti o destinazioni che risolvono in indirizzi privati. Il runner trova
   il proxy tramite `/etc/profile.d/runner-proxy.sh`.
9. **Chiavi SSH**: coppia dedicata Paperclip→runner generata in un container usa e getta; privata solo nei segreti
   del progetto (0600, fuori da Git) e, incollata a mano, in Paperclip (Environments); pubblica passata al runner come
   variabile. `known_hosts` con verifica attiva.

## Problemi verificati, cause e soluzioni collaudate

| Problema | Causa verificata | Soluzione collaudata |
|---|---|---|
| La sandbox di Codex non parte nel container | `bwrap` richiede namespace utente non privilegiati, bloccati dal seccomp di Docker e sull'host da `apparmor_restrict_unprivileged_userns=1` | Il confine è il container runner; bypass della sandbox di Codex ammesso **solo** nel runner |
| Con gli adapter locali l'agente può leggere i segreti del server | L'agente gira nel container di Paperclip con lo stesso utente (`/run/secrets`, `master.key`) | Esecuzione via SSH nel runner separato |
| `adapter_engine_unavailable` su SSH | Codex ACP supporta solo destinazioni sandbox | `adapterConfig.engine = "cli"` |
| Login di Codex e JWT temporaneo restano sul runner | Paperclip non cancella `/work/.paperclip-runtime/runs/<id>/` | `runner-session` chiude all'avvio di un nuovo incarico le esecuzioni non più collegate; `runner-janitor` le chiude dopo 90 s di inattività |
| Dopo tempo scaduto o annullamento il processo dell'agente continua sul runner | SSH senza terminale non termina il processo remoto alla chiusura della connessione | Un'esecuzione i cui processi non discendono più da una sessione `sshd-session` è abbandonata: processi terminati, file rimossi |
| Un incarico legge i file del precedente | La pulizia a tempo lasciava una finestra | Chiusura immediata all'avvio dell'incarico successivo |
| Due esecuzioni contemporanee si leggono i file | Stesso utente nello stesso container | **Un runner per un solo agente** e `maxConcurrentRuns: 1` |
| Una rete Docker con uscita raggiunge la LAN | NAT verso router, dispositivi della LAN e porta 80 dell'host (Caddy); UFW non filtra quel traffico | Runner solo su reti interne + `egress-proxy` |
| Segreti visibili con `docker inspect` | Variabili d'ambiente dichiarate nel Compose | Secrets come file + export nel processo |
| `pids_limit` rifiutato dal Compose | Conflitto con `deploy.resources.limits.pids` | Solo `deploy.resources.limits.pids` |
| Documenti montati come singolo file non aggiornati | Il bind di un file segue l'inode | Dopo modifiche a file montati singolarmente: ricreare il runner (le cartelle montate si aggiornano da sole) |

Dal runner l'API di Paperclip risponde 403 a ogni chiamata diretta, perché il nome host non è autorizzato: il lavoro
passa solo dal ponte sul canale SSH, con i permessi dell'agente (verificato: 403 su creazione di aziende, sulla
disattivazione dell'approvazione e sulla creazione diretta di agenti).

## Ipotesi smentite

- **"Paperclip inoltra tutto l'ambiente del server al runner SSH"**: falsa per v2026.916.1. Collaudo con segreti
  fittizi su 24 comandi SSH, compresi gli ausiliari: nessun segreto amministrativo arriva al runner. Il processo di
  Codex riceve solo l'ambiente costruito per l'esecuzione; il token reale dell'agente resta nel server, e il runner
  riceve un token del ponte casuale e temporaneo.
- Di conseguenza **non serve un'immagine Paperclip modificata**.

## Tentativi da non ripetere

- Disattivare il bypass o usare Landlock legacy nel container di Paperclip: la sola lettura blocca anche la rete
  (il Chief non raggiunge l'API) e lascia leggibili i segreti; `workspace-write` va in errore.
- Abilitare i namespace utente o togliere seccomp/AppArmor: tocca l'host e aumenta i privilegi.
- Mettere il runner su una rete Docker con uscita.
- Affidarsi a tmpfs o a un'attesa fissa per la pulizia tra incarichi.
- Usare il "Paperclip Runner" (sperimentale, disattivato di default).
- Per cercare un ambiente di prova, lanciare `lxc` su Ubuntu: installa LXD da solo
  ([dettagli](../../trasversali/ubuntu-lxc-installa-lxd.md)).
- Ricostruire le immagini locali "per sicurezza": `docker build` reinstalla i pacchetti Debian non fissati e
  produce un'immagine diversa da quella collaudata (vedi aggiornamenti).

## Gestione delle chiavi

- **Rotazione della chiave SSH Paperclip→runner** (collaudata): generare la nuova coppia, sostituire la chiave
  pubblica autorizzata e ricreare il solo runner, incollare la nuova privata in Paperclip (Environments → modifica,
  senza screenshot), Test connection, verificare che la vecchia sia rifiutata, cancellarla ed eliminare il vecchio
  segreto in Paperclip.
- **Chiave host del runner**: non ruotarla senza aggiornare `known_hosts` in Paperclip.
- **Chiavi locali di Paperclip** (`<dati>/instances/default/secrets/` nel volume di Paperclip): `master.key` cifra i segreti
  aziendali (login OpenAI compreso) e `decision-signing.key` firma le decisioni. Senza queste, i segreti sono persi.

## Aggiornamenti (Paperclip, Codex, runner)

1. Leggere le note di rilascio e controllare che `packages/adapter-utils/src/remote-execution-env.ts` e il percorso
   SSH non siano cambiati; per Codex, che `engine: "cli"` e il comportamento su SSH siano invariati.
2. Backup del database e dei dati di Paperclip (chiavi locali comprese).
3. Rieseguire i banchi di prova separati sulla nuova immagine Paperclip e sulla nuova immagine del runner
   ([test/](test/README.md)).
4. Solo dopo: cambiare versione e digest nel Compose (e `CODEX_VERSION` e tag del runner), aggiornare, poi le
   verifiche della produzione.

## Rischi residui

- I token temporanei (ponte, variabili dell'esecuzione) compaiono negli argomenti dei processi e nei comandi SSH
  (proposte upstream #10229, #13303): accettato **solo per il collaudo iniziale**, nessun altro segreto al Chief.
- Codex nel runner gira senza sandbox propria: il confine è il container.
- Richieste di Codex negate dal proxy e non autorizzate: `api.github.com`, `files.openai.com`, `ab.chatgpt.com`,
  `sdmntprsouthcentralus.oaiusercontent.com` (BRU-2 riuscita senza). Ampliare l'elenco solo con approvazione.
- Dopo un'interruzione, se non parte un nuovo incarico, i file restano fino a 90 s.
- `egress-proxy` è sulla rete con uscita: raggiunge la LAN, ma il suo codice rifiuta ogni destinazione privata.
- Le immagini locali dipendono da pacchetti Debian non fissati alla ricostruzione.

## Test di regressione

Elenco e strumenti: [test/README.md](test/README.md). Minimo dopo ogni installazione o aggiornamento: le verifiche
della produzione (rete del runner, proxy, API, SSH, isolamento; solo dati fittizi).

## Applicazione in un progetto

Un'installazione concreta (per esempio BrundIA) conserva nel proprio repository Compose, script di gestione, runbook di
ricostruzione con i propri segreti e i dati: questa pagina ne è la base tecnica, non la sostituisce.
