# Dopo la foundation

Registro canonico: `register.json`, generato da `python3 bin/ops-questions.py sync`.
Il completamento della base non completa le questioni, non certifica produzione e non concede accessi.
STATUS e rapporto finale devono rimandare qui, senza una seconda lista concorrente.

L'amministratore legge AGENTS, STATUS, KB applicabile e `python3 bin/ops-questions.py next`.
Presenta un mandato breve: risultato atteso, procedura/skill applicabile, strumenti, permessi già validi,
prove e recupero. Una questione alla volta. Nessuna ricostruzione teorica dell'azienda o delle policy.

Per `kind=decisione` compila nel JSON analysis, alternatives e recommendation: stato osservato,
alternative concrete, costi/interruzioni, soluzione consigliata e recupero.
Poi `advance ID approvazione --evidence RIF_PROPOSTA`; solo dopo un'approvazione umana reale
registra `approvata`, quindi `esecuzione`, `verifica`, `chiusa` con riferimenti reali.
Il registro non autentica la persona e non sostituisce i permessi della macchina.

Per `kind=attivita`, `requires_approval=false`, l'operazione ordinaria gia autorizzata puo passare
da analisi a esecuzione con analysis e recommendation compilate e riferimento alla policy in evidence.
Non chiedere conferme per aggiornamenti ordinari, letture, documentazione o recuperi gia autorizzati.
Se emerge un cambiamento incompatibile, una spesa, un rischio concreto non coperto o una modifica
di privilegi/rete, fermare l'azione e ottenere la decisione necessaria prima di eseguirla.
Sudo continua a richiedere la password del proprietario nel terminale; nessun privilegio generale nuovo.

Le dipendenze 10/10b sono un unico tema backup: prima definire cosa salvare, dove, retention,
cifratura e recupero; poi configurare e provare, senza dichiarare coperto cio che non e verificato.
La copia remota non si completa dal nome OFFSITE. Il gate di manutenzione rimane vincolante.
Quando si completano le configurazioni, aggiornare host.conf, ESCLUSIONI, stato, decisioni e prove;
`sync` non chiude automaticamente le voci e una ripresa foundation non reinserisce i rinvii rimossi.
La modalita completa richiede `FOUNDATION_ONLY="no"` e parametri/prerequisiti effettivi: non impostarla
solo per togliere avvisi o dichiarare il server pronto.

`collect` rileva in sola lettura anomalie finalrd nel boot precedente ed eventi correnti del journal.
Un evento segnalato richiede analisi, non prova automaticamente un guasto corrente o una causa.
La KB non raggiungibile resta un task; l'assenza di accesso ai log non e prova di salute.
Non modificare link o disabilitare servizi per nascondere errori di spegnimento.

Nessun segreto nel registro, nei log condivisi o in Git. Conservare storia, prove, approvazioni e fallimenti.
Il registro non esegue comandi. Non confonderlo con KB tecnica o memorie di aziende/progetti.

## Mandato di collaudo VM

Prima di proporre attivazioni, distinguere il mandato corrente del proprietario:
collaudo del pacchetto su VM oppure amministrazione verso la produzione. `--vm`
non autorizza da solo backup permanenti, offsite, spese o riavvii successivi.
Con mandato di collaudo, registrare difetti del pacchetto, comportamento atteso,
file coinvolti, modifica minima e prove; non trasformarli in decisioni di produzione.

Per il collaudo dopo foundation usare unicamente:
`sudo ops-installa --collaudo-backup-vm` (RC4 o successiva, VM riconosciuta e base completata).
Il comando usa integrita e snapshot del pacchetto, lock e log standard. Esegue due backup
Borg/borgmatic con dati sintetici, due ripristini con confronto di contenuti e metadati,
rotazione log e controllo repository. Workspace temporaneo root 0700, rimosso anche in errore;
nessun dato reale o segreto viene incluso, nessun cron o configurazione permanente installati.
Lo stato `test-backup-vm` separato riporta fatto/errore e il codice reale. In errore leggere
il log e ripetere lo stesso comando: nuova prova isolata, nessun passo manuale intermedio.
Non cancella altri repository. La prova non e una modalita di attivazione del backup reale.

Non impostare BORG_REPO e non rimuovere 10/10b dalle esclusioni dopo questa prova.
Le questioni 10 e 10.3 restano aperte: il risultato non prova copertura dei dati reali,
offsite o cron notturno e non approva la manutenzione di produzione.
Il passo 10 reale installa anche il cron; non usarlo per una prova temporanea.
L'attivazione permanente dopo foundation resta un mandato distinto, da definire con
policy reali; non esiste ancora un comando che completi solo 10/10b riconciliando tutti
quegli stati. Non presentare gli script manuali come quel comando.

Log di esecuzione: usare il percorso gestito /var/log/ops-installa e run_logged del
flusso deterministico, con permessi leggibili dall'amministratore e codice reale.
Non dare per leggibile la home dagli agenti. Non usare pipe con tee come prova di
successo: senza gestione esplicita del codice dello script mascherano i fallimenti.
Un dry-run puo creare file temporanei: non promettere assenza assoluta di scritture.

## Sospensione e ripresa

`advance ID sospesa --evidence RIF_MOTIVO` conserva storia e approvazione precedente,
ma esclude la questione dalla selezione next e dal vincolo della questione attiva.
Non annulla modifiche gia eseguite: documentare stato reale e recupero ancora necessario.
`report` continua a mostrarla. Per riprenderla usare
`advance ID analisi --evidence RIF_NUOVO_MANDATO`: l'approvazione corrente viene svuotata,
la storia resta e una decisione richiede una nuova approvazione prima dell'esecuzione.
Non chiudere una questione per sbloccare le altre e non riscrivere la storia.
