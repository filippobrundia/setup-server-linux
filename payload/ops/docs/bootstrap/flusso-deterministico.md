# Bootstrap: flusso deterministico — 2026-10-12

## Requisito e decisione
Le approvazioni ordinarie della chat non soddisfacevano il requisito gia concordato. La configurazione iniziale non viene piu delegata al modello. Il punto di ingresso comune esegue la procedura dal terminale SSH reale, indipendentemente da Claude, Codex, Antigravity o Gemini.

## Comando e comportamento
Locale: bash installa-server.sh --agente antigravity --profilo docker --esclusioni "7.1 10.3 11.2 12.8".
Pubblico dopo il rilascio: install.sh con --configura, profilo, esclusioni e SHA-256 verificata.

Installa-server prepara il bootstrap. Configura-server rileva i dati del server, scrive le sole chiavi previste, registra decisioni e parametri in Git, verifica il piano, guida il login del solo agente scelto senza aprire una chat di lavoro, esegue sudo ops-installa e salva il rapporto. Passa l'impronta di host.conf: se i parametri cambiano dopo la preparazione, nessun passo viene eseguito. Restano i controlli delle impronte dei programmi e il riferimento di root.

Dopo un'interruzione o riavvio: configura-server. I parametri sono conservati e ops-installa riprende dallo stato persistente. Un errore resta un errore: il programma non sostituisce la correzione di un difetto con un'approvazione globale.

## Interventi personali rimasti
Credenziali della KB e del fornitore scelto, password sudo, conferma di un nuovo login SSH dopo il firewall, riavvio presidiato e approvazione della finestra automatica se inclusa. Nessun permesso AI per ip, findmnt, letture diagnostiche, Git o piano. Non si garantisce un numero fisso di password: la cache sudo puo scadere mentre si installano i pacchetti.

## Prove
Il banco mirato usa rilevamento e piano reali nella fixture, con login e sudo simulati, senza chiamate ai modelli. Ha passato i casi dei quattro agenti, login fallito, codice 5 e ripresa, errore installer, parametri incompatibili, rifiuto di root e argomenti arbitrari. Le chiamate simulate verificano che l'impronta dei parametri raggiunga l'installer.
La regressione completa include casi dell'installer reale con piano dichiarato e parametri modificati, oltre ai controlli precedenti. Gli esiti completi sono nei log sul server amministratore; il percorso appena introdotto deve ancora essere provato sulla VM pulita.

## Limiti e produzione
Esclusi nel laboratorio rete statica, copia remota, Healthchecks e attivazione manutenzione. Gate e manutenzione restano bloccati dalla copia remota assente. Il successo del cron KB reale, alcune prove di robustezza e il login Gemini API restano non dimostrati. Il programma di configurazione non abilita spese e non elimina questi limiti.
Nessun bootstrap eseguito sul N100. Nessuna release ufficiale pubblicata durante questa correzione.

## Esito della regressione e controllo mirato
Le due suite complete su Ubuntu 24.04 e 26.04 hanno passato 327 controlli su 328; l'ultimo ha eseguito tutti i casi del flusso con successo e poi fallito per shellcheck non ancora installato nel banco. Corretto l'ordine del banco, il controllo viene ripetuto separatamente. Nessun esito 327/328 viene presentato come 328/328 della suite originale. Il piano installato usa ora una libreria di root, non il file modificabile nel workspace; il test di manomissione verifica che il file del workspace non venga eseguito. I punti di ingresso mantengono stdin collegato al terminale anche se install.sh viene avviato da una pipe.

## Decisione del proprietario e collaudo VM, 12 ottobre 2026
Il proprietario accetta Antigravity per login e preparazione, purché un comando conduca il setup senza approvazioni dei comandi ordinari. Al termine il terminale propone Antigravity, Codex, Claude o Gemini, oppure termina senza aprire chat. La scelta non ripete il setup; un altro fornitore può richiedere il proprio login. Le credenziali, il nuovo accesso SSH del firewall e il riavvio restano interventi personali espliciti.
La VM pulita ha concluso il percorso deterministico con codice installer 0, profilo docker ed esclusioni 7.1, 10.3, 11.2, 12.8. Rapporto e repository pulito verificati via SSH dopo il riavvio. Il menu finale è una modifica successiva: viene provato separatamente con login e chat simulati, non viene attribuito al precedente collaudo VM. Nessuna pubblicazione effettuata.

## Consolidamento del percorso accettato
Un comando locale/pubblico avvia l'automatismo, senza una chat incaricata di ricostruire i passi. Antigravity può essere scelto per il primo login; a configurazione conclusa il menu apre l'agente amministrativo preferito. Il rilevamento guidato non ripete la lista delle decisioni già dichiarate né invita a lanciare altri comandi; il firewall guidato mostra solo la conferma richiesta dall'installer. Il login Antigravity spiega prima dell'apertura che la chat va chiusa con Ctrl-D per proseguire. Codex consulta direttamente il suo stato di login. Le regole Gemini sono passate a policy TOML, senza togliere sandbox o blocco sudo.
Prove reali di accesso del 12 ottobre: risposta minima Codex e Antigravity riuscita con codice 0. La prima prova Codex via SSH aveva stdin aperto ed è scaduta in attesa di input: ripetuta con /dev/null ha risposto. Non attribuire quel timeout al fornitore. Non sono dimostrati né la validità della chiave Gemini rifiutata né il riconoscimento del piano Claude.
