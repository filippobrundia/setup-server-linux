# Test riutilizzabili — Paperclip con runner isolato

Solo dati e credenziali **fittizi**. Pagina tecnica: [../README.md](../README.md).

## Automatici

| Strumento | Uso | Effetti |
|---|---|---|
| `check-runner.sh` | dopo installazione, ripristino o aggiornamento: dal runner reale raggiungibili solo Paperclip:3100 e il proxy; proxy (`proxytest.mjs`); API di Paperclip negata senza credenziali (`apitest.mjs`); SSH solo con chiave, root e inoltro rifiutati; isolamento del filesystem; nessun residuo di esecuzione | nessuno; container usa e getta |
| `check-runner.sh --codex` | anche l'uscita di Codex dal proxy (401 atteso) | invia a OpenAI una chiave **fittizia** |
| `probe.mjs` | raggiungibilità TCP da dentro un container: `node probe.mjs '[[nome,host,[porte]],…]'` | nessuno |
| `proxytest.mjs` | casi ammessi e vietati del proxy (variabili `EGRESS_PROXY`, `ALLOW`, `DENY`) | nessuno |
| `fake-codex.mjs` | finto `codex` per i banchi di prova: registra ambiente, argomenti dei processi e file, prova il ponte, i permessi, l'isolamento e i residui; modalità `ENVTEST_MODE=ok|fail|sleep`, percorsi `ENVTEST_DOCS` e `ENVTEST_FORBIDDEN` | nessuno (non contatta modelli) |

Gli script si lanciano da dentro il runner con `docker exec -i <runner> node --input-type=module - < script.mjs`.

## Banchi di prova separati (metodo)

Progetto Compose usa e getta con reti interne, nessuna porta, Paperclip in modalità `local_trusted`, segreti
amministrativi **fittizi** e riconoscibili, un runner con `fake-codex.mjs` al posto di Codex (opzione `command`
dell'agente). Da eseguire prima di adottare una nuova versione di Paperclip o del runner:

1. **Ambiente inoltrato**: creare azienda, segreto con chiave SSH usa e getta, ambiente SSH, agente `codex_local`
   (`engine: cli`), risvegliarlo; cercare i valori fittizi (senza stamparli) in ambiente, argomenti dei processi,
   comandi SSH registrati con un `ForceCommand` di prova, file fotografati durante l'esecuzione, log SSH e log
   dell'esecuzione. Attesi: nessun segreto amministrativo; token del ponte e variabili dell'agente solo nel runner.
2. **Pulizia**: esecuzioni riuscite consecutive senza attesa, fallita, per tempo scaduto (`timeoutSec` breve),
   annullata (`POST /api/heartbeat-runs/<id>/cancel`), due agenti contemporanei; dopo ciascuna contare le cartelle di
   esecuzione, gli `auth.json` e i processi rimasti. Attesi: nessuna lettura tra incarichi, nessun residuo dopo
   l'attesa, nessuna interferenza con esecuzioni attive.
3. **Permessi via ponte**: con l'agente, tentare creazione di aziende, disattivazione dell'approvazione e creazione
   diretta di agenti. Attesi: 403.

Un'implementazione completa dei banchi esiste nel repository del progetto BrundIA (non pubblico): `tests/envtest/` e
`tests/runner/`.

## Prove reali (con account e approvazione del proprietario)
Test connection dell'ambiente SSH in Paperclip; conversazione di collaudo con l'agente (lettura della documentazione,
scrittura negata, esecuzione sul runner nei log, host usati nel registro del proxy, nessun `auth.json` sul runner
dopo l'attesa, login ancora attivo); persistenza dopo `down`/`up`.
