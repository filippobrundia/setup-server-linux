# Guida unica — setup senza login AI

Da una sessione SSH normale, come amministratore, senza anteporre sudo:

```bash
bash installa-server.sh --profilo docker --esclusioni "7.1 10.3 11.2 12.8"
```

Gli script installano la base, tutti i quattro agenti e i prerequisiti. La Knowledge Base è facoltativa: se privata richiede il suo token, indipendente dagli account AI. Parametri ed esclusioni sono dichiarati prima di procedere; il setup rileva lo stato reale, verifica il piano, configura il sistema e salva il rapporto. Nessun login né chiamata a modelli AI durante il setup.

Restano password sudo, nuovo login SSH per confermare il firewall, riavvio presidiato e, se inclusa e con prerequisiti verificati, approvazione della manutenzione. Dopo il riavvio rientra via SSH e lancia `configura-server`: i passi completati non si ripetono e non viene chiesto un login AI.

A setup riuscito compare il menu: Antigravity, Codex, Claude, Gemini CLI oppure termina. Solo se scegli di aprire un agente viene chiesto il suo login e verificato l'accesso al modello e alle istruzioni condivise. Gli altri agenti restano installati, senza credenziali e senza bloccare il server. Puoi scegliere più tardi con `agente`.

Rapporto: `/srv/ops/docs/bootstrap/esito-configurazione.md`. Log: `/var/log/ops-installa/`. Il passo 12.7 verifica ambiente e sandbox dei quattro, non l'accesso ai modelli. Gli aggiornamenti automatici dei CLI si abilitano separatamente dopo login e verifica; la finestra del server mantiene i suoi prerequisiti di backup.

Le esclusioni non sono verifiche superate. Copia remota mancante: gate e manutenzione automatica restano bloccati. Il percorso pubblico si verifica dopo una pubblicazione; per collaudare il candidato basta l'archivio locale verificato.

La memoria condivisa è in `/srv/ops`: ogni agente legge AGENTS.md e STATUS.md, confronta il sistema reale, aggiorna documenti, configurazione dei controlli, decisioni e CHANGELOG, poi registra in Git. Un nuovo servizio/container va documentato anche per volumi e copertura del backup. Non esiste un agente AI che osserva continuamente i cambiamenti: gli script monitorano e l'agente interviene quando invocato.
