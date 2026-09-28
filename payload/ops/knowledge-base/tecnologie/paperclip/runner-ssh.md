# Runner SSH isolato per agenti Codex di Paperclip

**Stato:** verificato (Paperclip v2026.916.1, Codex 0.155.1, OpenSSH 10.0p2, 2026-09). Contesto e problemi:
[README.md](README.md). Artefatti: [riferimento/](riferimento/README.md).

## Perché
Con gli adapter locali l'agente gira nel container di Paperclip e ne può leggere segreti e chiavi; la sandbox di
Codex non funziona in un container non privilegiato. Si sposta l'esecuzione in un container dedicato, raggiunto da
Paperclip con un **ambiente SSH**: il confine di isolamento è il container del runner.

## Come funziona (verificato)
- Paperclip, a ogni esecuzione, copia via SSH (`tar`) il workspace e una `CODEX_HOME` ridotta (configurazione, skill,
  `auth.json` del login) in `/work/.paperclip-runtime/runs/<id>/`, avvia `codex` e alla fine recupera il workspace.
- Il processo riceve solo l'ambiente costruito per l'esecuzione (identificativi, `CODEX_HOME`, variabili configurate
  nell'agente); nessun segreto amministrativo del server (verificato con segreti fittizi su tutti i comandi SSH).
- Le chiamate dell'agente a Paperclip passano da un **ponte** sul canale SSH (`PAPERCLIP_API_URL` locale al runner) con
  un token casuale temporaneo; il server aggiunge il token reale dell'agente. Il runner non ha bisogno di raggiungere
  l'API (e dal runner le chiamate dirette sono rifiutate).
- Paperclip **non** cancella la cartella dell'esecuzione: senza il pulitore, login e token temporanei restano.

## Requisiti di configurazione
- Agente: ambiente SSH predefinito; `adapterConfig.engine = "cli"` (ACP non supporta SSH); `maxConcurrentRuns = 1`;
  bypass della sandbox di Codex ammesso **solo** qui.
- Un runner per **un solo agente** (stesso utente = esecuzioni contemporanee reciprocamente leggibili).
- Root in sola lettura; `/work`, `/tmp` e home in RAM; chiave host in un volume montato in sola lettura;
  documentazione dell'agente in sola lettura; solo reti interne; uscita tramite
  [proxy](../../trasversali/docker-reti-e-uscita.md).

## Pulizia delle esecuzioni (verificata in tutti i casi)
| Caso | Comportamento |
|---|---|
| riuscita, fallita | cartella dell'esecuzione chiusa all'avvio dell'incarico successivo o dopo `RUNNER_JANITOR_GRACE` |
| tempo scaduto, annullata | il processo resta vivo sul runner (SSH senza terminale, vedi [ssh-processi-orfani](../../trasversali/ssh-processi-orfani.md)): riconosciuto come abbandonato, terminato, cartella rimossa |
| esecuzioni contemporanee di agenti diversi | l'esecuzione attiva non viene toccata, ma si leggono a vicenda → un runner per agente |

## Chiavi
Coppia SSH dedicata Paperclip→runner (privata solo nei segreti del progetto e in Paperclip; pubblica al runner);
chiave host generata una volta e montata in sola lettura, impronta registrata in `known_hosts` con verifica attiva.
Rotazione: [README.md](README.md#gestione-delle-chiavi).

## Rischi residui
Valori delle variabili dell'esecuzione negli argomenti dei processi (client `ssh` e runner; proposte upstream
Paperclip #10229 e #13303); Codex senza sandbox propria nel runner; file residui fino a `RUNNER_JANITOR_GRACE` dopo
un'interruzione se non parte un nuovo incarico.
