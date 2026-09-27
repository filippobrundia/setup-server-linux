# Manutenzione automatica (aggiornamenti, riavvii, CLI)

Politica e limiti: `AGENTS.md` → "Politica di amministrazione". Qui: come funziona, come si installa e attiva,
dove guardare, come intervenire. Orari in **UTC**.
Sorgenti: `maint/` (script root `ops-maint`, unit, `install-maint`, modelli), `bin/cli-update`,
`bin/maint-approve`, `bin/quick-check`. Parametri: `/etc/ops-maint.conf` (root) e `/srv/ops/host.conf`.

## Calendario

| UTC | Cosa | Meccanismo |
|---|---|---|
| 03:00 | backup Borg (con eventuali snapshot SQLite) | cron `borgmatic` |
| 04:00 | copia remota del repository | cron `offsite-sync` |
| **dom 04:30** | **finestra**: aggiornamenti approvati, poi riavvio se richiesto | `ops-maint-window.timer` (root) |
| dom 05:15 | aggiornamento controllato dei CLI | `ops-cli-update.timer` (utente amministratore) |
| 06:00–07:00 | aggiornamenti di sicurezza Ubuntu | `apt-daily-upgrade.timer` → unattended-upgrades |

Gli orari non bastano a evitare sovrapposizioni. Finestra, `cli-update` e `install-maint` usano lo stesso
**blocco** `/run/lock/ops-maint.lock` (creato da `/etc/tmpfiles.d/ops-maint.conf`, aperto in sola lettura con
`flock`): chi lo trova occupato per più di 30 secondi rinvia (`heartbeat` lo tocca per un istante ai minuti 2,
7, 12…). La finestra tiene il blocco fino al riavvio. Backup e APT non usano quel blocco: la finestra controlla i
loro processi e i blocchi APT (`lslocks`) all'inizio **e subito prima del riavvio**.

## Installazione e attivazione (una volta, in ordine)

`install-maint` è il componente generico estratto dall'installatore del server di origine: installa solo file di
manutenzione, **non** installa pacchetti, non tocca repository APT, rete o servizi, non riavvia.

| Passo | Comando | Prerequisito verificato dal comando |
|---|---|---|
| 1. file, unit, stato (nessuna unit abilitata) | `sudo /srv/ops/maint/install-maint install --admin <utente>` | utente normale nel gruppo `sudo` |
| 2. verifica dopo i riavvii | `sudo /srv/ops/maint/install-maint enable postboot` | parametri validi |
| 3. timer della finestra | `sudo /srv/ops/maint/install-maint enable window` | postboot abilitato, `quick-check --gate` pulito (backup compresi) |
| 4. approvazione della finestra | `APPROVED=yes` in `/var/lib/ops-maint/inbox/window.conf` | approvazione del proprietario registrata in `docs/decisions.md` + primo riavvio presidiato riuscito |
| 5. timer dei CLI | `sudo /srv/ops/maint/install-maint enable cli-update` | `bin/cli-update --verify` superato (login fatto, permessi conformi, AGENTS.md caricato) |

Stato in qualunque momento: `/srv/ops/maint/install-maint status`. Disattivare: `install-maint disable …`.
`install` è rieseguibile: file identici saltati, file nostri diversi sostituiti con copia `.bak-<data>`, file
altrui mai toccati (si ferma). `/etc/ops-maint.conf` e `window.conf` non vengono mai sovrascritti.

## Componenti e permessi

| Cosa | Dove | Proprietà |
|---|---|---|
| Script root (finestra, postboot, `procs`, `origins`) | `/usr/local/sbin/ops-maint` | root:root 0755 — modificabile solo con sudo |
| Parametri | `/etc/ops-maint.conf` (`ADMIN`, `REQUIRED_UNITS`, origini e processi aggiuntivi) | root:root 0644, letto riga per riga, mai eseguito |
| Unit | `/etc/systemd/system/ops-*` | root:root 0644 |
| Stato e storico | `/var/lib/ops-maint/` (`history.log`, `hold`, `postboot-pending`, `rollback/`, log APT) | root:root 0755 |
| Input degli agenti | `/var/lib/ops-maint/inbox/` (`window.conf`, `approved-upgrades`) | root:<amministratore> 2770 |
| Log CLI | `~/.local/state/ops/cli-update/` | amministratore |

Root non esegue codice modificabile senza sudo: `quick-check` viene eseguito come amministratore (`runuser`).
Gli input sono accettati solo se file regolari (non link), di root o dell'amministratore, ≤ 64 KB.
`window.conf` vale solo se contiene esattamente `APPROVED=yes`. `approved-upgrades` accetta solo righe
`pacchetto=versione`; ogni pacchetto deve essere installato, con candidato uguale alla versione approvata, e la
simulazione non deve rimuovere nulla né usare origini diverse da Ubuntu (release della macchina), Docker CE e
quelle aggiunte in `EXTRA_ORIGINS_RE`. Una riga non valida crea `hold`.

## Finestra di manutenzione

In ordine, e si ferma al primo "no":

1. blocco libero; nessun `hold`; se esiste ancora `postboot-pending` → `hold`;
2. `window.conf` con `APPROVED=yes` (altrimenti non fa nulla);
3. c'è qualcosa da fare: lista approvata valida o `/var/run/reboot-required`;
4. nessun lavoro attivo (borg/borgmatic, rclone, apt/dpkg/unattended-upgrade, Claude, Codex, Antigravity,
   Gemini, processi di `EXTRA_BUSY_ARG_RE`), nessun blocco APT, nessuna sessione interattiva usata nelle ultime
   2 ore. Elenco attuale: `/usr/local/sbin/ops-maint procs`;
5. `quick-check --gate`: nessun ERRORE e nessuna attenzione nei backup;
6. container con restart policy; unit di `REQUIRED_UNITS` e `ops-postboot` abilitate all'avvio.

Poi: scarica in `rollback/` i `.deb` delle versioni installate (quando il repository li offre ancora), installa
la lista (`NEEDRESTART_MODE=a`), attende fino a 5 minuti che il sistema torni sano; se non torna sano reinstalla
le versioni precedenti disponibili e crea `hold`. Prima del riavvio: se la configurazione di rete generata da
netplan è cambiata → `hold`, niente riavvio; se nel frattempo è partito un lavoro o una sessione → rinvio.
Scrive `postboot-pending` e riavvia.

Rinvii: `RINVIO: <motivo>` in `history.log`, riprova la domenica dopo. Prova senza effetti:
`sudo DRY_RUN=1 /usr/local/sbin/ops-maint window`.

### Esecuzione presidiata

`sudo ops-maint attended`, da un terminale con il proprietario **fisicamente presente** (monitor e tastiera
collegabili): stessa sequenza, ma non richiede `APPROVED=yes` e non si ferma per le sessioni e gli agenti aperti;
backup, APT, salute e restart policy restano obbligatori. Procede solo se si scrive `SI`. Usata per il primo
riavvio e ogni volta che un rischio concreto richiede presenza fisica.

### Dopo il riavvio

`ops-postboot.service` (solo se esiste `postboot-pending`) attende fino a 10 minuti che `quick-check --gate` sia
sano. Sano → `OK dopo il riavvio` nel log. Non sano → `ERRORE`, `hold`, unit **fallita**.

### `hold`: manutenzione sospesa

Creato da ogni errore. Un agente verifica (`history.log`, `apt-window.log`, `systemctl --failed`,
`quick-check`), corregge o ripristina, registra, poi fa rimuovere il file (`sudo rm /var/lib/ops-maint/hold`).

## Recupero: cosa è reale e cosa no

- **File di configurazione**: copia `<file>.bak-<data>` accanto; Borg salva ogni notte `/etc/ops-maint.conf`,
  `/etc/apt/sources.list.d`, `/usr/local/bin` e `/srv/ops` (sorgenti di script e unit).
- **Pacchetti di repository che conservano le versioni precedenti** (es. Docker): la finestra le scarica in
  `rollback/` prima di aggiornare e le reinstalla se i servizi non tornano sani.
- **Pacchetti Ubuntu**: **nessun rollback garantito**, l'archivio conserva solo l'ultima versione.
- **Kernel**: il precedente resta installato; si sceglie dal menu GRUB. **Serve accesso fisico**.

## Aggiornamenti ordinari (agente in sessione)

1. `apt list --upgradable`; origine (`apt-cache policy`), simulazione, note di rilascio per ciò che tocca servizi.
2. Senza interruzioni: script con controlli eseguito dall'amministratore con sudo (`NEEDRESTART_SUSPEND=1` se un
   riavvio è comunque previsto).
3. Con interruzioni (Docker, kernel, servizi): `bin/maint-approve PACCHETTO…` → finestra.
4. VERIFY e registrazione (CHANGELOG, `STATUS.md`).

## CLI amministrativi

| Strumento | Installazione | Autoaggiornamento in background | Aggiornamento |
|---|---|---|---|
| Claude Code (iniziale) | npm `~/.npm-global`, Node.js 22 da NodeSource | disattivato: `~/.claude/settings.json` → `env.DISABLE_AUTOUPDATER=1`, `autoUpdatesChannel=stable` | versione npm `stable`, solo se più nuova |
| Codex (facoltativo) | npm `~/.npm-global` | nessuno | npm `latest` |
| Antigravity (facoltativo) | `~/.local/bin/agy` | disattivato: `AGY_CLI_DISABLE_AUTO_UPDATE=true` | `agy update` |

`cli-update` aggiorna solo gli strumenti installati, un programma alla volta; se il programma è in uso rinvia;
dopo l'aggiornamento verifica permessi e caricamento di `AGENTS.md` con un prompt di prova non interattivo; se la
verifica fallisce reinstalla la versione precedente. `cli-update --verify` fa solo la verifica.
