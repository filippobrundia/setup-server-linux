# Agenti di amministrazione

Quattro agenti installati sempre dal bootstrap, tutti avviati in `/srv/ops` e tutti con le stesse istruzioni
(`AGENTS.md`) e lo stesso stato (`STATUS.md`, documenti, Knowledge Base). Le conversazioni restano separate, ciascuna
nello strumento che l'ha creata. L'**agente della sessione** è `AGENTE` in `host.conf`.

| Nome (risposta) | Programma | Account / accesso | Sandbox | Comandi ordinari fuori dalla sandbox |
|---|---|---|---|---|
| Claude Code (`claude`) | npm `~/.npm-global` | account Anthropic (abbonamento Claude) | bubblewrap + socat, `failIfUnavailable`, nessuna uscita automatica | `excludedCommands` + `permissions.allow` in `~/.claude/settings.json` |
| Codex CLI (`codex`) | npm `~/.npm-global` | account ChatGPT/OpenAI | bubblewrap (`workspace-write`, rete chiusa, `.git` protetto) | `~/.codex/rules/ops.rules` (`allow` = fuori dalla sandbox senza richiesta) |
| Antigravity CLI (`agy`) | root, `/opt/ops-agenti/antigravity/agy` | account Google personale, piano Individual gratuito | namespace del kernel, profilo AppArmor `ops-agy` | `command(...)` in `~/.gemini/antigravity-cli/settings.json` |
| Gemini CLI (`gemini`) | npm `~/.npm-global` | chiave API di Google AI Studio | sandbox nativa degli strumenti, bubblewrap + seccomp | stato reale del server leggibile nella sandbox; rete aggiuntiva soggetta ad approvazione |

In tutti: `sudo` vietato, nessuna modalità che salta sandbox o approvazioni, autoaggiornamento disattivato
(aggiornamenti: `cli-update` e `ops-agy`, `docs/runbooks/manutenzione.md`).

## Scegliere o cambiare agente: `agente`

```bash
agente            # (o /srv/ops/bin/agente) domanda, login del solo agente scelto, collaudo, avvio in /srv/ops
agente antigravity
agente --stato    # i quattro agenti: ambiente e sandbox, login; nessuna modifica
```

La domanda è "Con quale agente vuoi avviare la sessione? Claude Code / Codex CLI / Antigravity CLI / Gemini CLI"
(Invio = quello attuale). Poi: ambiente e sandbox dell'agente scelto (se non conformi non si avvia), login se manca,
collaudo operativo (`cli-update --verify NOME`: `AGENTS.md` caricato con uscita 0 e prova di isolamento, una o due
richieste al modello), registrazione in `host.conf` con commit, avvio. Se l'agente non è utilizzabile (login,
abbonamento, quota) propone di riprovare il login o di scegliere un altro agente. Cambiare agente non reinstalla nulla
e non tocca l'avanzamento della configurazione.

## Login da SSH con il browser del PC (solo per l'agente scelto)

Il server non ha browser: ogni login mostra un URL da aprire sul PC. Nessun servizio a pagamento va attivato.

**Antigravity CLI** (account Google personale):
1. dalla sessione SSH: `agente antigravity` (o `agente` e rispondere Antigravity);
2. `agy` mostra un URL di autorizzazione: copiarlo nel browser del PC, accedere con l'account Google e approvare;
3. il browser mostra un codice: incollarlo nel terminale SSH;
4. a login completato uscire da `agy` (`/quit` o Ctrl-D): `agente` esegue il collaudo e riavvia la sessione.
Il token resta in `~/.gemini/antigravity-cli/antigravity-oauth-token` (0600; sul server non c'è un portachiavi
grafico). Telemetria: impostazione dell'account Google (`enableTelemetry` disattivata sul server di origine).

**Claude Code**: `claude auth login` (abbonamento Claude, predefinito): URL nel browser del PC, codice nel terminale.
**Codex CLI**: `codex login --device-auth`: URL e codice nel browser del PC.
**Gemini CLI**: chiave creata nel browser del PC su <https://aistudio.google.com/apikey> (senza attivare la
fatturazione); `agente gemini` la chiede con input nascosto e la salva in `~/.gemini/.env` (0600). Mai in `/srv/ops`.

## Prerequisiti verificati prima della prima sessione

`bootstrap.sh` installa e verifica senza login (`cli-update --ambiente`, anche in `agente --stato`):
- programmi reali dei quattro agenti, eseguibili senza shell interattiva (come i timer);
- bubblewrap e socat; dove Ubuntu non ha un profilo per `/usr/bin/bwrap` (24.04) e la restrizione dei namespace è
  attiva, il profilo mirato `ops-bwrap` (indicato dalla documentazione di Claude Code); su 25.04+ quello di Ubuntu;
  prova reale: `bwrap --unshare-all` come amministratore;
- Codex: `codex sandbox` legge `/srv/ops` e non scrive nella home;
- Antigravity: binario e cartelle `root:root 0755`, profilo `ops-agy` caricato (`ops-agy verify`);
- Gemini CLI: `security.toolSandboxing=true`, contenitore completo disattivato, YOLO vietato. Il controllo
  `gemini-sandbox-check.mjs` usa il motore realmente installato, senza modello: legge AGENTS.md, SSH e journal,
  verifica scrittura nel workspace e rifiuto della scrittura nella home. API interna cambiata o sandbox non
  funzionante: ambiente non conforme, nessun avvio automatico fuori sandbox.
Nessuna sandbox dipende da Docker: Docker (passo 8 di `ops-installa`) può arrivare dopo.

## Limiti noti (2026-10-06)

- **Sandbox di Antigravity su Ubuntu**: senza profilo AppArmor non parte (`sbox: bringLoopbackUp: ioctl
  SIOCSIFFLAGS: operation not permitted`, osservato sul server di origine con agy 1.2.16) e in quella prova agy ha
  **rieseguito i comandi fuori dalla sandbox** (scrittura di prova nella home riuscita). Il profilo `ops-agy` su un
  binario di root è la soluzione proposta, **da verificare sulla VM**; la prova di isolamento di `cli-update --verify`
  fa fallire il collaudo se la scrittura riesce, quindi un ripiego silenzioso non passa.
- **Quota gratuita di Antigravity**: limitata e non documentata qui con numeri verificati; il collaudo usa due richieste.
- **Gemini CLI 0.63.0**: l'11 ottobre la sandbox nativa è stata provata sulla VM Ubuntu 26.04.1: legge servizi e
  journal dell'host, scrive nel workspace e protegge la home. Il collegamento al modello con chiave vera resta da
  collaudare. Nel piano gratuito della chiave API Google può usare i contenuti inviati per migliorare i prodotti.
- La prova di isolamento dipende dal modello: se l'agente non riporta il rifiuto, l'esito è "isolamento NON
  DIMOSTRATO" (mai dato per buono).
- `kb sync` esce con 0 anche quando usa la copia locale: il successo è solo la riga "sincronizzata:". La riuscita
  della sincronizzazione **dal cron** non è ancora dimostrata (l'output del cron è scartato).
