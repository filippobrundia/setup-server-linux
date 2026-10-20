# Foundation 0.8.0-rc.4 — collaudo dopo la base

Revisione incrementale, stabile 0.7.0 e RC3 immutate. Nessuna modifica a N100.

## VM RC3 gia completata

Conservare snapshot della VM e i log. Chiudere Claude durante l'aggiornamento del pacchetto.
I comandi vanno nel terminale SSH come amministratore normale.
Prima scaricare/verificare il pacchetto ed eseguire il controllo di compatibilita:

```bash
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.8.0-rc.4/install.sh | bash -s -- --check --no-kb --agente claude
```

Aggiungere `--sha256` con l'impronta della release per fissare anche il digest indipendente.
Se il controllo segnala conflitti, fermarsi e conservare l'output: non sovrascrivere file a mano.
Se termina con codice 0, applicare il pacchetto (senza --configura, senza rifare i passi foundation):

```bash
curl -fsSL https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.8.0-rc.4/install.sh | bash -s -- --no-kb --agente claude
```

Questa procedura e per la VM di prova con KB gia scollegata; non copiarla su altre macchine.
Il bootstrap aggiorna gli strumenti del pacchetto; conserva host.conf, documenti modificati,
registro e storia Git secondo i controlli di compatibilita. Non ignora conflitti o file locali
modificati. Non lancia configura-server, non installa backup reali, non riavvia la VM.

## Una prova, un comando

```bash
sudo ops-installa --collaudo-backup-vm
```

Esito atteso: COLLAUDO BACKUP VM SUPERATO, ESITO COLLAUDO BACKUP VM=0,
stato test-backup-vm fatto in /var/log/ops-installa/stato.
I log sono in /var/log/ops-installa/ultimo, leggibili dall'amministratore senza sudo.
Non aggiungere tee: il codice dello script viene gia conservato e registrato.

Prova Borg/borgmatic e logrotate reali con dati sintetici: due archivi, due ripristini,
contenuti, permessi, proprietario, symlink e integrita repository. La cartella temporanea
root 0700 e rimossa anche in errore. Non legge dati di produzione o credenziali, non
installa cron, non modifica BORG_REPO, esclusioni, passi reali 10/10b o approvazioni.
Non e collaudo della copertura del backup reale, dell'offsite o della pianificazione.
In caso di errore il codice e nonzero; dopo la diagnosi ripetere lo stesso comando,
senza riparazioni manuali di host.conf. La nuova esecuzione riparte con dati sintetici nuovi.
Non toccare altri repository per ripulire la prova.

## Ritorno all'agente

Riaprire Claude. Per la questione 10 approvata e sospesa solo nelle annotazioni:

```bash
python3 /srv/ops/bin/ops-questions.py advance 10 sospesa --evidence "Mandato del proprietario: collaudo pacchetto; precedente approvazione sospesa, decisione permanente rinviata"
python3 /srv/ops/bin/ops-questions.py next
```

Sono comandi documentali senza sudo. Non annullano modifiche eventualmente gia eseguite:
qui il proprietario ha riportato solo letture e documentazione prima della sospensione.
La storia e mantenuta. Una futura ripresa usa analisi e richiede una nuova approvazione,
non riutilizza quella sospesa. Le decisioni di produzione restano separate dal collaudo.
Chiedere all'agente di leggere log e stato del test, riferire prove e limiti, aggiornare
STATUS/CHANGELOG e poi diagnosticare finalrd in sola lettura, una questione alla volta.
Non chiedere destinazioni offsite o acquisti per portare a termine questa prova VM.

## Ripristino

La prova elimina soltanto i propri dati sintetici, non richiede rollback di configurazioni.
Per annullare l'aggiornamento del pacchetto usare lo snapshot VM preso prima: non fare
downgrade manuali dei singoli script e delle impronte. Il backup reale resta non configurato.

Per nuova VM pulita usare l'installer RC4 con --configura --profilo docker --vm; al reboot
riprendere con configura-server. Soste firewall e riavvio come nella guida RC3.
