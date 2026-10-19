# Revisione incrementale 0.8.0-dev — collaudo rapido su NUOVA VM

Base: v0.7.0, commit `6267824bca7a60f0b28c04f4614fa6b3ae51ad8a`.
Branch locale: `foundation/0.8.0-vm`. Non è una release pubblicata né una validazione di produzione.
Non eseguire su server esistenti. Nessun intervento su servern100 autorizzato da questa guida.

## Tre passaggi nella VM

Preparare una VM Ubuntu Server LTS pulita con console di recupero, snapshot iniziale,
utente amministratore normale e SSH. Usare Ubuntu 26.04 per confrontarsi con il collaudo precedente;
la compatibilità con altre LTS richiede la relativa suite. Copiare nella home l'archivio candidato
e SHA256SUMS forniti con questa revisione. Non usare `curl .../v0.7.0/install.sh`: installerebbe la versione stabile precedente.

1. Verificare ed estrarre, nella sessione SSH della **nuova VM**:

```bash
sha256sum -c SHA256SUMS
tar -xzf setup-server-linux-0.8.0-dev.tar.gz
cd setup-server-linux-0.8.0-dev
```

2. Installare il candidato come amministratore, con password sudo quando richiesta:

```bash
sudo bash bootstrap.sh --admin "$(id -un)" --login-dopo-configurazione
configura-server --profilo docker --vm
```

La KB resta facoltativa, token solo nell'input nascosto. Confermare il firewall da un secondo login
e il primo riavvio presidiato quando richiesti: sono controlli di accessibilità reali.
`--vm` verifica la virtualizzazione e registra i rinvii 7.1, 10.3, 11.2, 12.8;
non salta controlli del disco o il backup locale. Sono questioni da discutere, non requisiti soddisfatti.
Non sostituisce le esclusioni del laboratorio con una falsa attestazione di produzione.

3. Dopo il riavvio, o dopo una disconnessione:

```bash
configura-server
```

Il profilo e i rinvii sono persistenti. Alla fine si può scegliere l'agente o terminare senza login.
Leggere `/srv/ops/docs/bootstrap/esito-configurazione.md` e:

```bash
python3 /srv/ops/bin/ops-questions.py next
```

## Manutenzione indipendente dalle chat

Ubuntu security continua con unattended-upgrades, secondo configurazione verificata nell'installer.
I timer CLI sono indipendenti dal gate offsite e si possono attivare appena ambiente e sandbox sono conformi:

```bash
sudo /srv/ops/maint/install-maint enable cli-update
```

Questa operazione non richiede login AI e non chiama modelli. I timer aggiornano un CLI per volta,
verificano ambiente/sandbox e tentano il ripristino della versione precedente in caso di errore.
Il caricamento runtime di AGENTS e l'accesso ai modelli si verificano separatamente con `cli-update --verify`:
non sono certificati dal controllo deterministico, e possono dipendere da account/quote.

La finestra di aggiornamento sistema/riavvio mantiene approvazione iniziale e gate backup/salute:
non è attivata dal percorso VM finché offsite e altri prerequisiti non sono risolti.
Il nuovo `AUTO_UPGRADES=yes` nelle configurazioni **nuove** seleziona automaticamente upgrade ordinari;
non abilita timer e non autorizza da solo riavvii. Le configurazioni esistenti senza la chiave restano manuali.
Non chiedere approvazioni umane pacchetto per pacchetto quando policy e verifiche coprono l'operazione.

Selezione: indici APT esistenti, pacchetti già installati, candidato fissato, simulazione completa,
origini consentite dalla configurazione root e stessa release. Niente nuove dipendenze, rimozioni,
migrazioni di release, pacchetti fuori piano o candidati cambiati. Si rinvia se il recupero di un pacchetto
non è disponibile. Nessun aggiornamento eseguito dal registro delle questioni.
Il piano automatico vive in memoria e non scrive nell'inbox durante dry-run.
Lock condiviso, lavori attivi, servizi, backup, rete, hold e verifica postboot rimangono vincolanti.
Il timer settimanale non recupera una finestra persa fuori orario (`Persistent=false`).

Offsite non definito non blocca letture, registro, documenti, sync KB, sicurezza Ubuntu e timer CLI con
recupero proprio. Continua a bloccare finestra/riavvii che dipendono dal gate. Un testo OFFSITE o
un avvio cron non provano trasferimento e ripristino remoto: prima della produzione conservarne le prove reali.

## Registro: un argomento alla volta

`docs/admin-questions/register.json` è la fonte del percorso decisionale; `docs/decisions.md` conserva
le decisioni prese. STATUS rimanda al registro senza creare una seconda lista divergente.
`sync` importa i rinvii senza duplicarli e senza chiuderli quando spariscono da host.conf.
L'agente compila `analysis`, `alternatives`, `recommendation` con fatti verificati, rischio, recupero,
costi e scelta raccomandata; presenta al proprietario una questione importante per volta.

```bash
python3 /srv/ops/bin/ops-questions.py advance 10.3 approvazione --evidence 'Percorso della proposta preparata'
```

Solo dopo una vera risposta del proprietario registra `approvata` con riferimento datato;
poi `esecuzione`, `verifica` e `chiusa`, sempre con `--evidence` e prove reali. Il programma impone
sequenza e un solo argomento attivo, ma **non autentica la persona**: una registrazione non concede
permessi. Le approvazioni restano soggette alle regole reali della macchina e agli strumenti.
Un fallimento resta aperto, annotato nella history; non segnare chiusa una configurazione non verificata.
Nessuna password o URL contenente credenziali nel registro.
In caso di arresto durante una scrittura, verificare prima che non esista più un processo del registro;
solo allora rimuovere `.lock` e l'eventuale `.register.tmp`, preservando `register.json` e il suo Git.

## Prove automatiche e criteri di accettazione

Nel clone candidato, test isolati (Python standard + Bash; non modificano il sistema):

```bash
python3 tests/foundation-revision-test.py
```

Regressione Linux esistente, in container usa e getta (richiede Docker, scarica pacchetti):

```bash
bash tests/run-container-test.sh
IMAGE=ubuntu:26.04 bash tests/run-container-test.sh
```

Eseguire inoltre le suite di orchestrazione e agenti secondo README, in ambienti isolati;
non eseguire gli scenario root direttamente su una macchina da conservare.
I test locali nuovi non sostituiscono queste suite né certificano systemd, APT reale o riavvio.

Nella VM verificare:

- Installazione senza correzioni locali; ripresa dopo firewall, disconnessione e riavvio;
  i passi superati non si ripetono e il registro conserva history e approvazioni.
- Codici reali del rapporto; rinvii visibili, backup locale e restore effettivamente provati;
  offsite aperto, gate ancora non superato e nessuna dicitura produzione completa.
- Timer CLI attivi dopo il comando sopra, con esecuzione naturale e log; nessuna chiamata a modelli.
- Con offsite assente, `sudo env DRY_RUN=1 /usr/local/sbin/ops-maint window`
  non installa né riavvia. Verificare che inbox/stato non cambino dal dry-run.
- Dopo aver risolto le decisioni, approvare la finestra una volta sola secondo il runbook esistente;
  provare lock occupato, candidato cambiato, origine estranea, rollback indisponibile, errore APT,
  salute fallita, rete cambiata e postboot incompleto tramite mock o snapshot sacrificabile.
  Nessun reboot quando un prerequisito fallisce. Il recupero non riuscito deve risultare HOLD.
- Dopo il primo reboot di manutenzione, esito postboot reale e pending rimosso solo con verifica;
  controllare kernel, servizi e accessibilità da un nuovo SSH.

Ripristino VM: fermare i timer per evitare nuove esecuzioni, conservare i log fuori dalla VM e tornare
allo snapshot iniziale. I `.deb` precedenti sono recupero dei pacchetti, non ripristino completo dei dati
o del kernel. Non promettere rollback totale di migrazioni o servizi senza una prova dedicata.

## Stessa struttura futura su N100

Restano `/srv/ops`, AGENTS unico, STATUS, CHANGELOG, host.conf, docs, bin, maint e KB con Git separato.
L'unica aggiunta di struttura è `docs/admin-questions/register.json`, utilizzabile identica su ogni macchina.
Valori host, credenziali, servizi e storia restano specifici del server: non copiare la VM sul N100.
La struttura attuale reale di N100 non è stata letta in questa sessione e non è certificata uguale.

Migrazione N100 futura e separata: leggere AGENTS/STATUS reali, inventario e differenze rispetto al candidato;
preparare un diff che preservi policy locali e servizi, backup e ripristino verificati, approvazione del
perimetro, applicazione minima e verifica. Non eseguire bootstrap sul N100, non importare alla cieca il
template AGENTS e non sovrascrivere `/etc/ops-maint.conf`. Nessuno di questi passaggi è eseguito ora.
