# Foundation 0.8.0-rc.5 — chiusura del collaudo su Hyper-V

Revisione incrementale della RC4; versione stabile 0.7.0 e tag precedenti immutati.

## Correzioni

- Il controllo Antigravity conserva stderr e codice di uscita; una versione vuota
  e un errore esplicito. Il timeout invia SIGKILL cinque secondi dopo SIGTERM se
  il processo non termina. Questo non risolve uno stallo del kernel o della VM.
- Il bootstrap registra l'errore Antigravity e si arresta con codice nonzero,
  senza dichiarare completata la configurazione. Non salta un agente non verificato.
- Il passo firewall registra una sola stima di scadenza al momento dell'armamento;
  installer e script mostrano quella stessa stima. Il vero timer resta monotono.
  Alla ripresa di un vecchio timer privo della stima, il messaggio lo dichiara.
  Restano obbligatori nuovo accesso SSH e verifica delle regole; nessun bypass.

## Un solo ambiente di lavoro

Usare la prima VM Hyper-V gia completata con RC4: collaudo backup riuscito e
questione 10 sospesa da Claude. VirtualBox e le VM incomplete non sono il bersaglio.
Non usare 127.0.0.1:2222, che era l'inoltro VirtualBox. Accedere all'indirizzo
attuale della prima VM Hyper-V. N100 non fa parte di questa procedura.

Conservare un punto di controllo prima dell'aggiornamento, se serve recupero.
Chiudere la sessione Claude durante l'aggiornamento. Eseguire nel terminale SSH
come amministratore normale il blocco con checksum pubblicato nella release.
Il blocco controlla Hyper-V e foundation completata PRIMA di installare:

```bash
(
  set -euo pipefail
  [ "$(systemd-detect-virt)" = microsoft ] || {
    echo 'STOP: questa procedura richiede la VM Hyper-V scelta.'; exit 3;
  }
  [ -x /usr/local/sbin/ops-installa ] &&
    grep -q '^STATO: COMPLETATO FOUNDATION' /srv/ops/docs/bootstrap/avanzamento.md || {
    echo 'STOP: questa non e la VM con foundation completata. Nessuna modifica.'; exit 3;
  }
  url=https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v0.8.0-rc.5/install.sh
  curl -fsSL "$url" | bash -s -- --check --no-kb --agente claude
  curl -fsSL "$url" | bash -s -- --no-kb --agente claude
  /usr/local/bin/configura-server
)
```

Per fissare anche l'impronta dell'archivio usare il blocco della release, che
aggiunge --sha256 a entrambi i download. Gli errori fermano la sequenza.
Non usare --configura nell'installer per questo aggiornamento: la base e gia
completata. Il comando finale configura-server aggiorna il rapporto e la memoria.
Se compaiono un conflitto o uno STOP, conservare l'output e non sovrascrivere file.

## Criterio di chiusura

Aggiornamento pacchetto riuscito, rapporto FOUNDATION COMPLETATA con codici reali 0,
ambiente degli agenti conforme. Il backup con dati sintetici e la sospensione del
registro sono gia stati collaudati sulla stessa VM: non ripeterli senza un nuovo
errore pertinente. Dopo questo rapporto si riprende il lavoro con Claude/Chief.
Nessun nuovo giro su VM pulite richiesto da questa procedura.

Questo non certifica la produzione. Backup reale, offsite, finestra e finalrd
restano registrati, con i limiti gia documentati. Nessuna attivazione di servizi
di produzione e nessun riavvio aggiuntivo autorizzati da questa guida.

## Verifiche della revisione

Test mirati di errore/timeout Antigravity, arresto della pipeline bootstrap,
scadenza condivisa e conferma/rinvio/rollback firewall. Sintassi degli script e
integrita della distribuzione. Non ripetuta la regressione generale: limiti ed
esiti effettivi sono riportati nella release. Applicazione RC5 alla VM ancora da
verificare dal proprietario, non dichiarata riuscita in anticipo.
