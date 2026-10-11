# Guida unica — bootstrap 0.7.0

## Nuova macchina
Da SSH come amministratore, scaricare install.sh dal tag v0.7.0 e lanciarlo con l'impronta completa riportata nella release. La guida esterna alla release contiene il comando su una riga.
Il bootstrap installa Claude Code, Codex, Antigravity e Gemini con i prerequisiti. Chiede se collegare la KB, l'URL e il token di lettura nascosto. Poi chiede quale agente usare.

## Agente
Lanciare /srv/ops/bin/agente antigravity per account Google personale, codex per account ChatGPT, claude per account Anthropic, gemini per chiave API. Autenticare soltanto l'agente scelto. Gli altri non bloccano il collaudo per mancanza di login.
La sandbox deve consentire scrittura in /srv/ops e negarla nella home. Non procedere se questa prova fallisce.

Prompt iniziale:
Completa la configurazione iniziale seguendo AGENTS.md e la checklist. Rileva i dati reali, raccogli in una sola domanda quelli mancanti e il profilo desiderato, registra ogni esclusione, verifica ops-installa --piano e indicami il comando sudo ops-installa. Non dedurre il profilo base dalla sola assenza di container. Non cambiare i file del pacchetto o aggirare la sandbox. Leggi autonomamente i log e aggiorna la documentazione al termine.

## Comando unico
Nel terminale SSH reale: sudo ops-installa. Confermare con SI, aprire un nuovo login SSH per confermare il firewall, scrivere RIAVVIA al riavvio presidiato e rilanciare sudo ops-installa dopo l'avvio. I passi superati non vengono ripetuti. APPROVO serve soltanto per la finestra automatica quando i prerequisiti sono soddisfatti.
Le correzioni del collaudo sono integrate: una nuova installazione non richiede --dichiara-correzione. Non accettare correzioni sconosciute per superare il controllo di integrità.

## Esiti
COMPLETATO CON ESCLUSIONI significa laboratorio concluso, validazione produzione incompleta. Se manca la copia remota, gate e manutenzione restano bloccati. COMPLETATO senza esclusioni richiede tutti i controlli superati.
Prove e limiti: docs/bootstrap/chiusura-0.7.0.md. Per Gemini login e modello restano non provati; cron KB reale e prove di produzione restano nel backlog.
