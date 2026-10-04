# Configurazione base di un server nuovo

Checklist **eseguibile in ordine** per completare la base di questa macchina dopo la distribuzione del pacchetto
(`bootstrap.sh`). Riproduce la configurazione realizzata e collaudata sul server di origine e le decisioni di
`docs/decisions.md`; non introduce scelte nuove.

**Regole:** autonomia, sudo e consensi seguono `AGENTS.md`. I comandi `sudo` li esegue l'amministratore (l'agente
prepara lo script con controlli e rollback).
- ⚠️ **DISTRUTTIVO** — può cancellare dati: consenso del proprietario se sul disco c'è qualcosa che non sia stato
  appena creato dall'installazione.
- 🔌 **ACCESSO** — può interrompere l'accesso remoto (SSH, rete, firewall, privilegi): consenso del proprietario,
  una sessione già autenticata tenuta aperta durante la prova, accesso fisico disponibile.

Formato: **Controllo** (sola lettura) → **Se manca** (azione) → **Verifica**.
**Avanzamento:** `docs/bootstrap/avanzamento.md`, aggiornato con commit da `ops-installa` (sezione "Esecuzione unica").
Un'interruzione si riprende dal primo passo non completato: ogni controllo è ripetibile.
**Problemi:** si registrano in `STATUS.md` solo quando **riscontrati** su questa macchina; le voci "Controllo
ereditato" indicano cosa verificare perché sul server di origine era un limite noto.

Già fatto da `bootstrap.sh`: `/srv/ops` con regole, documenti e script; Node.js 22 (NodeSource) e Claude Code per
l'amministratore; adattatori nella home; componenti di manutenzione installati **senza** unit abilitate.

**Script dei passi** (`docs/bootstrap/passo*.sh`, collaudati su Ubuntu 26.04): eseguono i passi 3, 5–10 e le verifiche
del 12 con PRECHECK → BACKUP → MODIFICA → VERIFY, manifest in `/var/lib/ops-bootstrap/` e `--rollback`;
`verifiche-base.sh` controlla, in sola lettura, le voci senza uno script proprio (1, 2, 4, 7.1, 10.3, 11, 12.4–12.7).
Leggono i parametri da `host.conf` (riga per riga, senza eseguirlo) e da `/etc/os-release`. Coprono la base **senza
servizi**: dati, esclusioni e snapshot dei servizi restano passi manuali. Non si lanciano uno per uno: li esegue
`ops-installa` (sotto).

## Esecuzione unica (procedura normale)

Dopo la distribuzione: **un comando del proprietario** per tutta la parte privilegiata, poi solo autenticazioni e
conferme importanti. Niente sequenze di `sudo` a mano, niente script locali, niente output copiati in chat.

1. **Parametri (agente, senza sudo).** `bash /srv/ops/docs/bootstrap/rileva-parametri.sh` propone `LAN_CIDR`,
   `MOUNTS`, `DATA_MOUNT`, `SERVICES` ed elenca ciò che va deciso dal proprietario. L'agente gli fa **una sola
   richiesta** con tutto: `PROFILO` (`base` o `docker`), `ESCLUSIONI` (tra `2 7.1 10.3 11.2 12.8`, ognuna con il
   motivo), destinazione della copia remota, monitoraggio esterno. Poi `rileva-parametri.sh --scrivi --profilo …
   --esclusioni "…"`, controllo del diff, commit di `host.conf` e `ops-installa --piano` (sola lettura) senza
   problemi. Le esclusioni si registrano anche in `docs/decisions.md`. **Un'esclusione permette solo di chiudere il
   collaudo locale**: l'esito è "collaudo locale completato con esclusioni" (`STATO: COMPLETATO CON ESCLUSIONI`),
   la validazione per produzione resta incompleta. In particolare con 10.3 esclusa la copia remota mancante continua a
   bloccare `quick-check --gate`, `ops-maint attended` e l'attivazione e l'esecuzione della finestra: va esclusa
   anche 12.8 (`ops-installa` lo richiede).
2. **Comando unico (proprietario).** Da una **sessione SSH** dalla LAN (terminale vero; serve per confermare il
   firewall): `sudo ops-installa`. Una password; il programma mostra piano ed esclusioni e chiede `SI` una volta, poi
   esegue i passi in ordine (dry-run → esecuzione solo con dry-run a 0 → VERIFY) e si ferma al primo esito diverso
   da 0.
3. **Soste per una persona**, nella stessa esecuzione o rilanciando lo stesso comando:
   - **passo 7**: con UFW appena attivato (ripristino automatico armato per 10 minuti) aprire un **nuovo login SSH**,
     poi Invio nella sessione di `ops-installa`: il nuovo collegamento viene rilevato e la conferma data. Se si esce,
     rilanciare `sudo ops-installa` **dal nuovo login** prima della scadenza;
   - **12.4 riavvio presidiato**: scrivere `RIAVVIA` (con aggiornamenti in attesa e 12.8 non escluso il riavvio passa
     da `ops-maint attended`, che chiede `SI`); dopo l'avvio, da un nuovo login: `sudo ops-installa` (controlli dopo
     l'avvio e passi finali);
   - **12.8**: scrivere `APPROVO` per approvare la finestra di manutenzione automatica (l'agente lo registra in
     `docs/decisions.md`).
4. **Esiti (agente, senza sudo).** `/var/log/ops-installa/ultimo/riepilogo.log` (passi, codici, log), un file per
   comando con output e codice reale, `/var/log/ops-installa/stato`. `ops-installa` aggiorna da solo
   `avanzamento.md` (con commit) e scrive `STATO: COMPLETATO` solo con il passo 12 superato senza esclusioni
   (altrimenti `STATO: COMPLETATO CON ESCLUSIONI (…)`: validazione per produzione incompleta). L'agente completa poi
   `docs/` della macchina (overview, network, system, STATUS, CHANGELOG, decisioni).

Esiti di `ops-installa`: 0 completato · 1 passo non superato (correggere, poi rilanciare: riprende da quel passo, i
passi superati non vengono ripetuti) · 3 controlli iniziali (parametri, integrità, orario 03:00–04:10 e 06:00–07:00
UTC) · 5 in attesa di una persona. Un passo eseguito si annulla con `sudo ops-installa --rollback <passo>`.

**Garanzie.** Esegue solo gli script del pacchetto, confrontati con le impronte registrate da `bootstrap.sh` in
`/var/lib/ops-bootstrap/` (root) e lanciati da una copia di root: un file modificato ferma tutto prima di iniziare,
salvo una correzione accettata dal proprietario con `sudo ops-installa --dichiara-correzione <file>`. Nessun
`NOPASSWD`, nessun sudo interno, nessun comando arbitrario. Ogni comando gira in uno pseudo-terminale (`script`),
senza pipe sull'output di apt/dpkg.

---

## 0. Parametri della macchina

Compilare `/srv/ops/host.conf` (e annotare in `docs/overview.md`) leggendo i valori sulla macchina: nomi di
dispositivi, UUID, indirizzi e percorsi fisici non si copiano da altri server.

| Parametro | Dove | Si ricava da |
|---|---|---|
| hostname, utente amministratore | `HOST`, `ADMIN` (già compilati) | `hostname`, `bootstrap.sh` |
| rete locale ammessa | `LAN_CIDR` | router / `ip route` |
| interfaccia, IP/prefisso, gateway, DNS | `docs/network.md` | `ip -br addr`, `ip route`, `resolvectl status` |
| partizione per `/srv`, disco dati e suo punto di montaggio | `MOUNTS`, `DATA_MOUNT`, `docs/overview.md` | `lsblk -f` |
| repository Borg locale (`<DATA_MOUNT>/dati/backup/borg-repo-plain`) | `BORG_REPO` (a sezione 10 completata) | derivato |
| destinazione della copia remota | `OFFSITE` (solo descrittiva) | fornita dal proprietario; credenziali mai qui |
| servizi e container attesi | `SERVICES`, `CONTAINERS` | sezioni 7–8 |
| database SQLite da includere negli snapshot | `SQLITE_SNAPSHOTS`, `SNAPSHOT_DIR` | servizi della macchina |

Se la macchina ha un solo disco, `/srv` e `DATA_MOUNT` sono partizioni o cartelle dello stesso disco.
**Verifica:** `bash -n /srv/ops/host.conf`; commit.

## 1. Verifica iniziale (sola lettura)

1. **Hardware** — `lscpu`, `free -h`, `lsblk -o NAME,SIZE,TYPE,ROTA,TRAN,MODEL`, `journalctl -k -b -p err`:
   annotare gli errori del firmware già presenti (es. errori ACPI del BIOS), così da non confonderli in seguito.
2. **Ubuntu** — `lsb_release -ds`, `uname -r`: LTS supportata.
3. **Dischi** — `lsblk -f`, `findmnt --real`, `df -hT`, `cat /etc/fstab`, `swapon --show`.
4. **Rete** — `ip -br addr`, `ip route`, `resolvectl status`, `ls /etc/netplan/`, `ss -tulpn`.
5. **Accesso** — login SSH dell'amministratore, `sudo -v` riuscito, accesso fisico disponibile.

**Verifica:** `docs/overview.md` e la sezione "Il server in tre righe" di `AGENTS.md` compilati; commit.

## 2. Dischi e punti di montaggio

| Ruolo | Configurazione di riferimento |
|---|---|
| sistema | `/` ext4 + `/boot/efi` + file di swap dell'installer |
| amministrazione e servizi | partizione separata ext4 su `/srv`, opzioni `defaults,nofail` |
| dati e backup locale | btrfs `compress=zstd,noatime,space_cache=v2,nofail` (+ `ssd` se SSD) su `DATA_MOUNT` |

- **Controllo:** `findmnt /srv`, `findmnt <DATA_MOUNT>`, `grep -v '^#' /etc/fstab`.
- **Se manca:** ⚠️ **DISTRUTTIVO** `mkfs.ext4` / `mkfs.btrfs` solo su partizioni verificate vuote; riga in
  `/etc/fstab` **per UUID** (`blkid`) dopo la copia `fstab.bak-AAAA-MM-GG`. 🔌 Una riga errata può bloccare
  l'avvio: `sudo mount -a` e `findmnt --verify` **prima** di qualunque riavvio.
- **Verifica:** `findmnt --verify` pulito; `df -hT` mostra i ruoli; `MOUNTS` in `host.conf` aggiornato.
- **TRIM:** `systemctl is-enabled fstrim.timer` → `enabled` (default di Ubuntu); se manca e i dischi sono SSD/NVMe
  (`lsblk --discard` con valori non nulli): `sudo systemctl enable --now fstrim.timer`.

## 3. Struttura delle cartelle

| Percorso | Contenuto | Proprietà |
|---|---|---|
| `/srv/ops` | repository di amministrazione (già creato) | amministratore, 0775 |
| `/srv/docker` | data-root di Docker (interni: non toccare, fuori dal backup) **e** una cartella per servizio con compose e configurazione | root / per servizio |
| `<DATA_MOUNT>/dati/<servizio>` | dati persistenti dei servizi | per servizio |
| `<DATA_MOUNT>/dati/backup/` | `borg-repo-plain/`, `database/sqlite-snapshots/` | root 0750 |
| `/usr/local/bin`, `/usr/local/sbin` | script di backup; script root della manutenzione | root |

- **Controllo:** `ls -ld <DATA_MOUNT>/dati <DATA_MOUNT>/dati/backup`.
- **Se manca:** `sudo install -d -m 0750 <DATA_MOUNT>/dati/backup <DATA_MOUNT>/dati/backup/database`.
  Script: `passo3-cartelle.sh` (si ferma se `DATA_MOUNT` è in `/etc/fstab` ma non montato).
- **Verifica:** stesso controllo.

## 4. Repository `/srv/ops`

**Knowledge Base condivisa** (repository separato, copia in `/srv/ops/knowledge-base`): `/srv/ops/bin/kb status`.
Se non è stata recuperata dal bootstrap (repository privato): la chiave pubblica `~/.ssh/kb_deploy.pub` va registrata
dal proprietario come deploy key del repository, poi `/srv/ops/bin/kb init`. Da lì valgono SYNC BEFORE WORK e le
altre regole di `AGENTS.md`.

- **Controllo:** `git -C /srv/ops status` pulito; `git log --oneline | tail -1` = distribuzione del pacchetto.
- **Se manca:** rieseguire `bootstrap.sh` (ripetibile).
- **Verifica:** l'agente avviato con `claude` dalla home carica `AGENTS.md` (sezione 12, punto 7).

## 5. Utenti, gruppi e permessi

- **Controllo:** `id <ADMIN>`; `sudo grep -rn NOPASSWD /etc/sudoers /etc/sudoers.d`;
  `getent passwd | awk -F: '$7 !~ /(nologin|false)$/ && $1 != "sync"'` (`sync`, con shell `/bin/sync`, è atteso).
- **Stato atteso:** utenti con shell solo `root` e l'amministratore; amministratore nei gruppi `sudo`, `adm`, **mai**
  in `docker` né in `lxd` (decisione ereditata 2026-10-04: equivalgono a root senza password; l'installer di Ubuntu
  Server aggiunge il primo utente a `lxd`); sudo con password, nessun `NOPASSWD`; nessuna modalità degli agenti che
  salti le approvazioni.
- **Se manca:** 🔌 `sudo usermod -aG adm <ADMIN>`; `sudo gpasswd -d <ADMIN> lxd` (e `docker`); rimuovere un
  `NOPASSWD` solo dopo aver verificato che `sudo` con password funziona. Script: `passo5-utenti.sh` (gruppi; un
  `NOPASSWD` o un altro utente con shell lo fermano senza modifiche).
- **Verifica:** ripetere il controllo (i gruppi cambiati valgono dai login successivi).

## 6. Pacchetti di base

| Pacchetti | Uso |
|---|---|
| `git`, `curl`, `ca-certificates`, `gnupg`, `jq` | repository, download e chiavi, JSON negli script (in parte già installati) |
| `tmux`, `htop`, `btop`, `neovim`, `net-tools` | lavoro interattivo e diagnostica |
| `acl`, `sqlite3` | permessi condivisi; snapshot dei database SQLite |
| `ufw`, `fail2ban`, `unattended-upgrades` | sezione 7 |
| `borgbackup`, `borgmatic`, `rclone`, `fuse3` | backup, copia remota, montaggio degli archivi per il ripristino |
| `btrfs-progs` | solo se il disco dati è btrfs |
| `sysstat` | storico delle prestazioni |

- **Controllo:** `dpkg-query -W -f='${Status} ${Package}\n' <pacchetti> 2>&1 | grep -v '^install ok installed'`.
- **Se manca:** `apt-get -s install <mancanti>` (nessuna rimozione); se `borgmatic` è tra i mancanti, **prima**
  `sudo systemctl mask borgmatic.timer` (il postinst di borgmatic 2.0 abilita e avvia il timer: senza maschera
  partirebbe un secondo scheduler prima della sezione 10); poi
  `sudo apt-get -o DPkg::Lock::Timeout=600 install <mancanti>`; infine `sudo systemctl unmask borgmatic.timer` e
  `sudo systemctl disable borgmatic.timer` (timer mai partito). Un mascheramento preesistente non va tolto.
  Script: `passo6-pacchetti.sh`.
- **Verifica:** il controllo non stampa nulla; `systemctl is-enabled borgmatic.timer` → `disabled`, mai avviato.

## 7. Impostazioni di sistema

Script per 7.2–7.7: `passo7-impostazioni.sh` (verifica 7.2 e 7.4–7.7, attiva UFW con ripristino automatico armato,
`--confirm` dopo un nuovo login SSH). Richiede `LAN_CIDR`: la 7.1 va completata prima.

### 7.1 Rete
- **Controllo:** `ip -br addr`; `sudo cat /etc/netplan/*.yaml`.
- **Stato atteso:** interfaccia principale con IP statico in un file netplan proprio (indirizzo, route di default,
  DNS); segreti (es. WiFi) solo in file root 0600, mai nel backup.
- **Se manca:** 🔌 file netplan, `sudo netplan try` (ripristino automatico se non confermato), poi `sudo netplan apply`.
- **Verifica:** `ping -c3 <gateway>`, `getent hosts ubuntu.com`, nuovo login SSH al nuovo IP.

### 7.2 SSH
- **Controllo:** `sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication)'`.
- **Stato atteso (decisione ereditata 2026-08-02):** porta 22, `PermitRootLogin prohibit-password` (default),
  `PasswordAuthentication yes` dalla sola LAN, mitigato da UFW `LIMIT` e fail2ban.
- **Se manca:** 🔌 file in `/etc/ssh/sshd_config.d/`, `sudo sshd -t`, `sudo systemctl reload ssh`, sessione aperta.
- **Verifica:** nuovo login SSH riuscito.

### 7.3 Firewall UFW
- **Controllo:** `sudo ufw status verbose`.
- **Stato atteso:** deny in ingresso, allow in uscita, deny routed; `22/tcp LIMIT` da `LAN_CIDR`; porte dei servizi
  solo da `LAN_CIDR` (ed eventualmente dalla rete Docker interna verso un servizio in rete `host`); **nessuna
  regola aperta verso Internet**.
- **Se manca:** 🔌 nell'ordine `sudo ufw limit from <LAN_CIDR> to any port 22 proto tcp`, `sudo ufw default deny
  incoming`, `sudo ufw default allow outgoing`, `sudo ufw default deny routed`, `sudo ufw enable`; nuovo login
  prima di chiudere la sessione.
- **Verifica:** `ufw status verbose`; `ss -tulpn` con ogni porta spiegata in `docs/network.md`; `ufw` in `SERVICES`.

### 7.4 fail2ban
- **Controllo:** `sudo fail2ban-client status sshd`.
- **Stato atteso:** jail `sshd` attiva con la configurazione del pacchetto Ubuntu.
- **Se manca:** `sudo systemctl enable --now fail2ban`. **Verifica:** il controllo risponde; `fail2ban` in `SERVICES`.

### 7.5 Orario
- **Controllo:** `timedatectl show -p Timezone -p NTPSynchronized`.
- **Stato atteso:** `Etc/UTC`, `NTPSynchronized=yes` (`systemd-timesyncd` su 24.04; su Ubuntu 26.04 il client
  predefinito è **chrony**, che va mantenuto: vedi `docs/system.md`).
- **Se manca:** `sudo timedatectl set-timezone Etc/UTC`; `sudo timedatectl set-ntp true`.

### 7.6 Aggiornamenti automatici
- **Controllo:** `cat /etc/apt/apt.conf.d/20auto-upgrades`; `apt-config dump | grep -i Automatic-Reboot`.
- **Stato atteso:** contenuto di `maint/templates/20auto-upgrades`; `50unattended-upgrades` di default; riavvio
  automatico disattivato (default); repository esterni aggiornati solo tramite la finestra (sezione 9).
- **Se manca:** `sudo dpkg-reconfigure -plow unattended-upgrades`.
- **Verifica:** `sudo unattended-upgrade --dry-run` senza errori.

### 7.7 Log e spazio
- **Stato atteso:** journald di default e persistente (`/var/log/journal`); job cron con log in `/var/log/<nome>.log`;
  spazio controllato da `quick-check` (attenzione 80 %, errore 90 %).
- **Se manca:** `sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald`.
- **Rotazione dei log dei job cron:** per borgmatic il modello `maint/templates/logrotate-borgmatic` (sezione 10.2).
  **Controllo ereditato:** sul server di origine mancava anche per la copia remota; verificare dopo la sezione 10.3
  e registrare se manca.

## 8. Convenzioni per ospitare servizi

### 8.1 Docker (solo se la macchina ospita container)
- **Controllo:** `docker version`; `cat /etc/docker/daemon.json`; `apt-cache policy docker-ce`.
- **Stato atteso:** Docker CE dal repository ufficiale `download.docker.com`; `daemon.json` =
  `maint/templates/docker-daemon.json` (data-root `/srv/docker`, log `json-file` 100m × 3, `overlay2`).
- **Se manca:** repository e pacchetti secondo la procedura ufficiale Docker per Ubuntu; `daemon.json` **prima**
  del primo avvio del motore: il postinst di `docker-ce` avvia `docker.socket`/`docker.service`, quindi si
  mascherano entrambi prima dell'installazione, si valida `sudo dockerd --validate --config-file
  /etc/docker/daemon.json`, poi si smascherano e si avviano. **Nessun utente nel gruppo `docker`** (sezione 5): i
  comandi docker si danno con `sudo`. Aggiungere `docker` a `SERVICES` e `docker.service` a `REQUIRED_UNITS` in
  `/etc/ops-maint.conf`, modificando **solo la riga di assegnazione** `REQUIRED_UNITS=` (mai un grep sull'intero
  file, che trova anche i commenti) come unità separata da spazio. Script: `passo8-docker.sh`.
- **Verifica:** `sudo docker info --format '{{.DockerRootDir}} {{.LoggingDriver}}'` → `/srv/docker json-file`;
  `getent group docker` senza membri; `sudo /usr/local/sbin/ops-maint origins` accetta i parametri riletti.

### 8.2 Regole per ogni servizio
- cartella `/srv/docker/<servizio>/` con `docker-compose.yml` (nessun container creato con `docker run` a mano);
  dati in `<DATA_MOUNT>/dati/<servizio>/`; `docker compose config` prima di ogni avvio; restart policy su ogni
  container; nome in `CONTAINERS`;
- file bind-montati modificati senza rename atomico (`runbooks/modifica-file-bind-montati.md`);
- segreti in `.env` o file 0600, esclusi dal backup normale, con la sola posizione in `docs/security.md`;
- accesso da Internet solo tramite tunnel in uscita verso il reverse proxy (con cloudflared: repository
  `pkg.cloudflare.com`, `--no-autoupdate`, origine aggiunta in `EXTRA_ORIGINS_RE`, `TUNNEL_READY_URL`); nessuna
  porta aperta verso Internet;
- una scheda `docs/services/<servizio>.md`.
- **Controllo ereditato:** sul server di origine alcune credenziali erano leggibili con `docker inspect` (variabili
  d'ambiente); verificare `docker inspect -f '{{.Config.Env}}' <container>` e registrare se succede.

## 9. Manutenzione automatica

I file sono già installati da `bootstrap.sh` (`install-maint install`), **nessuna unit abilitata**. Non esiste e
non va cercato un installatore unico: si attiva un componente alla volta, quando il suo prerequisito è
soddisfatto (`docs/runbooks/manutenzione.md`, tabella "Installazione e attivazione").

- **Controllo:** `/srv/ops/maint/install-maint status`; `cat /etc/ops-maint.conf`.
- **Se manca:** `sudo /srv/ops/maint/install-maint install --admin <ADMIN>` (ripetibile).
- **Parametri:** `REQUIRED_UNITS` (servizi essenziali abilitati all'avvio), `EXTRA_ORIGINS_RE`,
  `EXTRA_BUSY_ARG_RE` in `/etc/ops-maint.conf` (sudo, con commit della descrizione in `docs/system.md`).
- **Verifica:** `sudo DRY_RUN=1 /usr/local/sbin/ops-maint window` senza errori di parametri. Script:
  `passo9-manutenzione.sh` (`REQUIRED_UNITS` dalle unità di `SERVICES` in `host.conf`, nessuna unit abilitata).
- **Attivazione:** `enable postboot` prima del collaudo (sezione 12, punto 4); `enable window` e `enable
  cli-update` nel collaudo finale.

## 10. Backup

### 10.1 Repository e configurazione
- **Controllo:** `sudo borgmatic config validate`; `sudo borg info <BORG_REPO>`.
- **Stato atteso (decisioni ereditate 2026-09-24):** repository Borg locale **non cifrato**; configurazione da
  `maint/templates/borgmatic-config.yaml` con i sorgenti di sistema, i dati e le configurazioni **non sensibili**
  dei servizi, le esclusioni dei file con segreti; retention, compressione e controlli del modello.
- **Database SQLite:** snapshot fail-safe prima del backup (`before_backup`). Lo script `sqlite-snapshots.sh`
  **non è nel pacchetto** (sul server di origine è un file root non ancora estratto e verificato): va prima estratto dal
  server di origine con sudo, riletto e parametrizzato. Senza, niente `before_backup`.
- **Se manca:** ⚠️ `sudo borg init --encryption=none <BORG_REPO>` solo su cartella vuota; configurazione in
  `/etc/borgmatic/config.yaml`; `sudo install -o root -g root -m 0750 maint/templates/run-borgmatic.sh
  /usr/local/bin/run-borgmatic.sh`; `sudo borgmatic config validate`.
- **Verifica:** `config validate` pulito; `BORG_REPO` in `host.conf`. Script (base senza servizi):
  `passo10-backup.sh` (repository, configurazione, primo backup, cron, prova di ripristino).

### 10.2 Pianificazione
- **Stato atteso:** `/etc/cron.d/borgmatic` = `maint/templates/cron-borgmatic` (03:00); `borgmatic.timer`
  disabilitato e mai partito (mascherato durante l'installazione, sezione 6); `/etc/logrotate.d/borgmatic` =
  `maint/templates/logrotate-borgmatic` (`delaycompress`: dopo la rotazione `quick-check` legge l'archivio dal log
  precedente).
- **Se manca:** copiare i modelli; `sudo systemctl disable --now borgmatic.timer`.
- **Verifica:** dopo la prima notte `quick-check` segnala l'archivio recente e lo scheduler unico. Script:
  `passo10b-rotazione-verifica.sh` (rotazione reale forzata, `quick-check` trova l'archivio, secondo backup e
  ripristino).

### 10.3 Copia remota
- **Stato atteso:** `/etc/cron.d/offsite-sync` da `maint/templates/cron-offsite-sync` (04:00, `rclone sync`),
  remote rclone di root con credenziali fornite dal proprietario (nuova destinazione o nuovo account: consenso).
- **Verifica:** `sudo rclone check --size-only <BORG_REPO> <REMOTE:percorso>` → 0 differenze; `OFFSITE` in `host.conf`.
- **Controlli ereditati:** (a) con `rclone sync` la copia remota è uno specchio: verificare se la destinazione
  conserva versioni o blocca le cancellazioni; se no, registrare in `STATUS.md` che un danno locale si propaga;
  (b) verificare se le credenziali indispensabili al ripristino (remote rclone, eventuali chiavi) esistono
  anche fuori dal server; se no, registrarlo in `STATUS.md`.

## 11. Monitoraggio e notifiche

1. **Controllo rapido:** `host.conf` completo; `bin/quick-check` senza ERRORE; `bin/quick-check --gate` exit 0.
2. **Segnale esterno:** passaggi personali del runbook `monitoraggio-esterno.md` (chiave API inserita dal
   proprietario), poi `bin/healthchecks setup`.
   **Verifica:** `bin/healthchecks test-start` → stato `down` ed email ricevuta → `bin/healthchecks test-end` →
   stato `up` ed email di ritorno.

## 12. Collaudo finale

1. **Backup presidiato:** `sudo /usr/local/bin/run-borgmatic.sh`; `sudo borg list <BORG_REPO>`; log senza errori.
2. **Prova di ripristino** (in una cartella temporanea poi eliminata): `borg extract` di `/srv/ops` → identico
   (`diff -r`) e `git fsck` ok; configurazioni estratte identiche; database con `PRAGMA integrity_check` = `ok`.
   Script per il ripristino di `/srv/ops`, UFW, porte e montaggi (12.2, 12.5, prima della 12.4): `passo12-verifiche.sh`.
   **Controllo ereditato:** il ripristino completo dalla copia remota non era mai stato provato sul server di origine:
   se non lo si prova qui, registrarlo in `STATUS.md`.
3. **Copia remota:** `rclone check --size-only` con 0 differenze.
4. **Primo riavvio presidiato:** `sudo /srv/ops/maint/install-maint enable postboot`, poi con il proprietario
   presente `sudo ops-maint attended` (se non c'è nulla da fare, un normale `sudo reboot` concordato). Dopo il
   rientro: `findmnt --verify` pulito; `systemctl --failed` vuoto; container `Up`; `journalctl -b -1` disponibile.
   **Controllo ereditato:** `journalctl -b -1 | grep -iE 'failed unmounting|target is busy'` — sul server di origine
   `/srv` non veniva smontato allo spegnimento; se succede, registrarlo.
5. **Accessi:** nuovo login SSH; `ufw status verbose` e `ss -tulpn` conformi.
6. **Monitoraggio:** `bin/quick-check` senza errori; Healthchecks `up`.
7. **Agenti:** `bin/cli-update --verify` superato (AGENTS.md caricato, permessi conformi).
8. **Attivazione:** `sudo /srv/ops/maint/install-maint enable window`; approvazione della finestra da parte del
   proprietario registrata in `docs/decisions.md`, poi `APPROVED=yes` in `/var/lib/ops-maint/inbox/window.conf`;
   `sudo /srv/ops/maint/install-maint enable cli-update`.
9. **Chiusura:** `docs/` della macchina, `STATUS.md` ("Dove siamo rimasti": base completata), `CHANGELOG.md`;
   in `docs/bootstrap/avanzamento.md` la riga `STATO: COMPLETATO`; commit. Da qui si segue la gestione
   ordinaria di `AGENTS.md`.
