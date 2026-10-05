# Knowledge Base: collegamento, token e sostituzione

La Knowledge Base (KB) è **facoltativa** e il repository lo sceglie il proprietario: nessun collegamento
predefinito. Foundation e KB restano separate: senza KB la foundation funziona normalmente.

## Durante il bootstrap (ogni nuovo server)

```
Vuoi collegare una Knowledge Base? [S/N]
```
- **N** → "KB non configurata per scelta" (registrato in `kb.conf`: la domanda non torna).
- **S** → `Inserisci l'URL HTTPS del repository della Knowledge Base:` (es. `https://github.com/<utente>/<repo>.git`).
  Prima si prova **senza credenziali** (repository pubblico). Se serve autenticazione: `Incolla il token…` con
  **input nascosto**. Mai la password dell'account GitHub.
- Se l'accesso non riesce: `1` correggere l'URL, `2` reinserire il token, `3` riprovare, `4` continuare senza KB.
  La foundation non viene reinstallata.
- Con l'accesso verificato: copia locale in `/srv/ops/knowledge-base`, sincronizzazione ogni 6 ore (crontab
  dell'amministratore), nessun'altra autenticazione.

Più tardi, senza sudo e da un terminale vero (SSH o console): `/srv/ops/bin/kb collega`.

## Token di lettura per GitHub (da preparare UNA SOLA VOLTA)

1. GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens** →
   **Generate new token**.
2. **Token name**: per esempio `kb-lettura-server`. **Expiration**: una data, per esempio un anno.
3. **Resource owner**: l'account che possiede la KB. **Repository access**: **Only select repositories** → solo il
   repository della KB.
4. **Permissions** → **Repository permissions**: **Contents: Read-only**. GitHub aggiunge da solo **Metadata:
   Read-only** (obbligatorio). Nessun altro permesso.
5. **Generate token**, copiarlo e salvarlo **subito nel gestore di password**, con la data di scadenza (GitHub non lo
   mostra più).

Mai un token "classic" né uno con accesso a tutti i repository. Sui nuovi server basta incollarlo quando richiesto.

## Dove sta il token sul server

- `~/.config/ops-kb/token` dell'amministratore che sincronizza la KB: cartella 0700, file 0600, fuori da `/srv/ops`
  e da ogni repository.
- Escluso dai backup della foundation: `/home` non è tra le sorgenti, e il modello di borgmatic esclude comunque
  `/home/*/.config/ops-kb`.
- Git lo riceve solo dall'helper `kb credenziale`, che legge il file e lo consegna per il solo host della KB. Non
  compare negli URL, negli argomenti dei processi, nell'ambiente, nei log, nel crontab o nei commit. `kb.conf`
  contiene solo l'URL e il percorso del file.

## Scadenza, revoca, sostituzione

- **Scaduto o revocato**: `kb sync` scrive "ACCESSO NEGATO alla Knowledge Base", **conserva la copia locale** ed
  esce con 0, così la gestione del server continua. `kb status` mostra l'ultimo errore.
- **Sostituirlo**, da un terminale vero, senza sudo:
  ```bash
  /srv/ops/bin/kb token
  ```
  Chiede il nuovo token (input nascosto), verifica l'accesso e solo allora sostituisce il file e sincronizza. Se la
  verifica fallisce, il token precedente resta.
- **Lo stesso token su più macchine**: se lo revochi o scade, va sostituito su **tutte** le macchine che lo usano
  (`kb token` su ciascuna). Prima di revocarlo, crea il nuovo token e aggiornale.
- **Cambiare repository**: `kb collega` dopo aver spostato la copia locale; oppure, se non è mai stata collegata:
  `kb collega`.

## Lettura e scrittura restano separate

Un server collegato via HTTPS **legge soltanto**: `kb publish` rifiuta di pubblicare. La pubblicazione dei record
resta ai server con scrittura autorizzata e al loro collegamento SSH, che questo flusso non tocca. Le installazioni
precedenti con deploy key continuano a funzionare com'erano.
