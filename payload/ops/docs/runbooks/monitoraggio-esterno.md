# Monitoraggio esterno (Healthchecks.io)

Decisione ereditata (2026-09-27): Healthchecks.io, piano gratuito, notifiche email; **un controllo per
macchina**, con il nome dell'host. Serve a sapere ciò che nessun controllo locale può dire: che il server è
spento, isolato o non è ripartito.

## Cosa viene inviato

Solo un segnale tecnico: una richiesta HTTPS **senza corpo** a `https://hc-ping.com/<uuid>` (successo) o
`…/fail` (problema), user agent `<host>-heartbeat`. Nessun log, nessun nome di servizio, nessun contenuto.

| Segnale | Quando |
|---|---|
| successo | ogni 5 minuti (cron utente `2-59/5 * * * * /srv/ops/bin/heartbeat`) se il server è sano, oppure solo "vivo" durante la manutenzione o subito dopo un riavvio di manutenzione |
| `/fail` | due controlli consecutivi di `quick-check --gate` con ERRORE, oppure manutenzione sospesa (`hold`) |
| nessuno | server spento, senza rete o bloccato → allarme dopo **periodo 5 min + tolleranza 15 min** |

Il cron è sfasato (minuti 2, 7, 12…) per non toccare il blocco di manutenzione alle 04:30 e alle 05:15.

## Dove sono le cose

| Cosa | Dove (`MONITOR_CFG` in `host.conf`, di default `~/.config/ops`) |
|---|---|
| Script del segnale | `bin/heartbeat` (utente amministratore, nessun sudo) |
| Configurazione e prove | `bin/healthchecks setup|status|test-start|test-end` |
| Chiave API read-write (credenziale) | `$MONITOR_CFG/healthchecks-api-key` (0600) — mai nel repository né negli output |
| URL di ping (chi lo conosce può inviare segnali falsi) | `$MONITOR_CFG/healthchecks-ping-url` (0600) |
| UUID del controllo | `$MONITOR_CFG/healthchecks-check` |

## Passaggi personali (una volta, li fa il proprietario dell'account)

1. Account su <https://healthchecks.io> (piano gratuito; si può usare l'account e il progetto già esistenti:
   un controllo in più per questa macchina).
2. Nel progetto: **Settings → API Access → Create API key** (read-write).
3. In una sessione SSH sulla macchina, incollare la chiave senza mostrarla:
   ```bash
   install -d -m 700 ~/.config/ops && ( umask 077; read -rsp 'Chiave API Healthchecks: ' k; echo; printf '%s\n' "$k" > ~/.config/ops/healthchecks-api-key )
   ```

Il resto lo fa l'agente: `bin/healthchecks setup` (crea il controllo, collega le integrazioni del progetto,
salva l'URL, installa il cron, invia il primo segnale).

## Prova dell'allarme (collaudo; da ripetere dopo modifiche)

1. `bin/healthchecks test-start` — sospende il cron, periodo e tolleranza a 1 minuto.
2. Entro 2–3 minuti `bin/healthchecks status` deve dire `down` e arriva l'email di allarme.
3. `bin/healthchecks test-end` — ripristina cron e valori (300 s + 900 s), invia un segnale: stato `up` ed
   email di ritorno alla normalità.

## Limiti

- Un solo controllo: distingue "muto" da "problema segnalato", non quale servizio è guasto (lo dice
  `quick-check` in sessione).
- Se Healthchecks.io stesso non è raggiungibile non arrivano allarmi; se il server perde solo la connessione
  verso Internet, l'allarme arriva anche se i servizi in LAN funzionano.
- Il piano gratuito conserva 100 eventi per controllo: lo storico lungo resta nei log locali.
