# Esperimento 2026-09: isolare gli agenti Codex di Paperclip

Paperclip v2026.916.1, Codex 0.155.1, Docker 29.8, Ubuntu 24.04. Soluzione risultante:
[tecnologie/paperclip](../tecnologie/paperclip/README.md). Sequenza reale, compresi errori e ipotesi smentite.

| # | Tentativo / ipotesi | Esito | Cosa ne resta |
|---|---|---|---|
| 1 | Paperclip in container con uid 1000 e senza capability | **riuscito** | configurazione di riferimento |
| 2 | Disattivare il bypass della sandbox di Codex nel container di Paperclip | **fallito**: `bwrap` non crea namespace utente (seccomp di Docker, `apparmor_restrict_unprivileged_userns=1`) | non ripetere senza cambiare i privilegi |
| 3 | Landlock legacy di Codex | **fallito**: in sola lettura blocca anche la rete e lascia leggibili i segreti; `workspace-write` va in errore | non ripetere |
| 4 | Ipotesi: "Paperclip inoltra tutto l'ambiente del server al runner SSH" (da lettura del codice) | **smentita** da un collaudo con segreti fittizi su tutti i comandi SSH | lezione: verificare le ipotesi di sicurezza con un test positivo prima di correggere |
| 5 | Immagine Paperclip modificata per filtrare l'ambiente | **non costruita**: inutile dopo il punto 4 | — |
| 6 | Codex su SSH con motore predefinito | **fallito**: `adapter_engine_unavailable` (ACP solo per sandbox) | `engine: "cli"` |
| 7 | Runner SSH separato | **riuscito**: nessun segreto amministrativo nel runner, ponte funzionante, permessi limitati all'agente | configurazione di riferimento |
| 8 | Pulizia con tmpfs e attesa fissa | **insufficiente**: interruzioni lasciavano processi e `auth.json`; un incarico immediato leggeva il precedente | chiusura delle esecuzioni abbandonate e all'avvio della successiva |
| 9 | Più agenti sullo stesso runner | **limite strutturale**: si leggono i file a vicenda | un runner per agente, `maxConcurrentRuns: 1` |
| 10 | Runner su rete Docker con uscita | **scartato** dopo misura: raggiunge LAN, router e servizi web dell'host | reti interne + proxy dedicato |
| 11 | `lxc` per cercare un ambiente di prova | **errore**: ha installato LXD | [ubuntu-lxc-installa-lxd](../trasversali/ubuntu-lxc-installa-lxd.md) |
| 12 | Collaudo reale con abbonamento OpenAI | **riuscito**: lettura della documentazione in sola lettura, scrittura negata, pulizia, persistenza | circa 250.000 token in ingresso per una conversazione a causa di ~20 letture sequenziali (86% in cache): preferire un indice iniziale e letture raggruppate |
