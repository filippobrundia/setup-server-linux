# Guida unica — configurazione deterministica

Da una sessione SSH normale, come amministratore:
- Pacchetto locale estratto: bash installa-server.sh --agente antigravity --profilo docker --esclusioni "7.1 10.3 11.2 12.8"
- Percorso pubblico, dopo la pubblicazione: bash install.sh --sha256 IMPRONTA --agente antigravity --configura --profilo docker --esclusioni "7.1 10.3 11.2 12.8"

Un comando prepara il bootstrap, collega eventualmente la KB, guida il login del solo agente scelto, rileva i dati dell'host, registra i parametri, esegue il piano, lancia ops-installa e salva il resoconto. Non aprire una conversazione AI per configurare la base.

Interventi personali: credenziali KB e agente, password sudo (il numero dipende dalla durata della cache), nuovo login SSH per il firewall, RIAVVIA per il riavvio, APPROVO per la manutenzione soltanto se inclusa e con prerequisiti soddisfatti.
Dopo il riavvio o un errore: configura-server. I parametri sono conservati e i passi superati non vengono ripetuti. Il programma non aggira errori, controlli di integrita o blocchi della manutenzione.

Rapporto: /srv/ops/docs/bootstrap/esito-configurazione.md. Log reali: /var/log/ops-installa/. Dopo la configurazione, agente NOME apre la normale sessione amministrativa.

Le esclusioni consentono il collaudo locale; non sono verifiche superate. Senza copia remota gate e manutenzione automatica restano bloccati. Gemini richiede API key; Antigravity usa login Google. Le quote e l'accesso del modello possono bloccare il suo collaudo: nessun servizio a pagamento viene attivato.

Il comando dichiara il piano e passa all installer l impronta dei parametri: se cambiano fra preparazione e avvio, nessun passo parte. Restano i controlli di integrita, la conferma di correzioni locali, firewall, riavvio e manutenzione.
