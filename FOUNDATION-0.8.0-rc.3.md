# Foundation Linux 0.8.0-rc.3 — prova completa su VM

Revisione incrementale della 0.7.0 congelata. Pre-release per laboratorio, non per N100 o server esistenti.
Conservare la VM precedente e i suoi log. Per una prova da zero usare una nuova VM Ubuntu Server 26.04
o una copia dello snapshot preso prima del bootstrap, con console e snapshot di recupero disponibili.
Entrare in SSH come amministratore normale.

## Installazione e ripresa

```bash
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.8.0-rc.3/install.sh | bash -s -- --configura --profilo docker --vm
```

Usare dopo la pubblicazione della pre-release e dei suoi asset. Per fissare anche l'impronta indipendente
aggiungere `--sha256` e il valore nella pagina della release. Se manca curl, installare solo curl e
ca-certificates con APT e ripetere. L'URL breve setup.brundia.com rimane sulla 0.7.0 stabile;
la sua destinazione non viene modificata da questa revisione.

Soste: password sudo; KB facoltativa con token nascosto se scelta; nuovo SSH per verificare il firewall;
primo riavvio presidiato. Nessuna chiamata ai modelli o acquisto.
Per una prova senza KB aggiungere `--no-kb`, registrando esplicitamente la scelta.
Una KB richiesta ma non collegata genera un'attivita e non blocca la foundation indipendente.
Errori reali di integrita, installazione, montaggi, servizi essenziali o sandbox restano bloccanti.

Quando compare la richiesta UFW, entro dieci minuti aprire un secondo SSH dal PC lasciando il primo aperto.
Se funziona, tornare subito alla prima sessione e premere Invio. Non lanciare un secondo installer.
Il timeout disattiva il firewall per proteggere l'accesso: non equivale a conferma riuscita.

Alla richiesta di riavvio scrivere `RIAVVIA`. Dopo il nuovo accesso SSH:

```bash
configura-server
```

La modalita e i rinvii sono persistenti. Non ripete i passi conclusi. In modalita foundation termina
direttamente con il rapporto e codice finale: nessun menu o login AI obbligatorio.

## Esito atteso

- `FOUNDATION COMPLETATA`, codice installer 0 e codice finale 0.
- SSH, UFW, fail2ban, cron e Docker attivi; montaggi e controlli postboot superati.
- Quattro CLI e sandbox conformi senza login: non certifica accesso ai modelli o contesto runtime.
- Timer CLI attivati senza login, indipendenti da backup/offsite; finestra sistema/reboot non attivata.
- Registro amministrativo persistente, rapporto finale e memoria locale compilati.

La foundation non decide il backup al posto del proprietario: copertura, destinazione, retention,
cifratura e prove di ripristino sono rinviate insieme ai passi 10/10b. Nessun backup/restore viene
dichiarato pronto. Restano da trattare offsite, rete stabile, monitoraggio e finestra.
Il codice zero della foundation non certifica produzione. Il vero `quick-check --gate` continua a
bloccare la manutenzione che dipende da backup/offsite: l'installer distingue quel gate dalla salute
necessaria a concludere la sola base.

La sync KB fallita resta dichiarata nel rapporto e come task. Un fallimento finalrd osservato nel
journal precedente genera un task tecnico: non e risolto ne certificato innocuo; nessun servizio
viene disabilitato per nascondere errori. Il collaudo naturale di cron/timer resta una prova separata.

## Lavoro dell'amministratore dopo la base

```bash
agente
```

L'agente scelto legge AGENTS, STATUS, la KB applicabile e `python3 bin/ops-questions.py next`.
Presenta mandato, procedura/skill applicabile, strumenti, permessi e risultato atteso.
Una questione alla volta: analisi, alternative, raccomandazione, approvazione umana reale,
esecuzione e verifica. Le normali attivita gia autorizzate non richiedono conferme banali.
Backup e relativo collaudo sono una sola decisione. Procedura in `docs/admin-questions/README.md`.
Il registro non autentica approvazioni, non concede privilegi e non esegue comandi.

La struttura /srv/ops e replicabile su N100, ma policy, valori, servizi e storia restano locali.
Non copiare la VM sul N100; la futura migrazione richiede lettura dello stato reale e autorizzazione separata.

## Prove prima del test VM

```bash
python3 tests/foundation-revision-test.py
python3 tests/memoria-iniziale-test.py
python3 tests/public-installer-test.py
bash tests/run-container-test.sh
IMAGE=ubuntu:26.04 bash tests/run-container-test.sh
```

Le suite scenario vanno in container sacrificabili, mai come root sul server da conservare.
Usare i soli file distribuibili, senza cache Python o altri file locali ignorati.
Le prove isolate coprono checksum LF/CRLF, corruzioni, duplicati, ripresa e registro con commenti;
il flusso root simulato verifica firewall, reboot, rinvii e conclusione con timer CLI.
Non sostituiscono installazione, timer naturale, APT/rollback o reboot reali della RC3.
Conservare `/srv/ops/docs/bootstrap/esito-configurazione.md` e i log in /var/log/ops-installa.
