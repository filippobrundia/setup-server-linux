# Knowledge Base tecnica — indice

Conoscenza tecnica **verificata e trasferibile** per gli amministratori del server (persone o assistenti tecnici).
Non riguarda gli agenti applicativi (per esempio i dipendenti di BrundIA).

**Knowledge first.** Prima di installare, configurare, aggiornare o diagnosticare un componente, cercare qui. Se esiste
una soluzione verificata, controllarne l'applicabilità (versioni, condizioni) e riutilizzarla prima di indagare.
**Learn & consolidate.** Chiudendo un lavoro tecnico significativo, riuscito o no, portare qui ciò che si è
verificato; aggiornare questo indice e, se possibile, i test. Regole complete: `AGENTS.md` della foundation.

Le pagine valgono per le versioni indicate in ciascuna. Nessun segreto, indirizzo o dato riservato: le
configurazioni specifiche di un'installazione restano nei rispettivi progetti.

## Tecnologie

| Argomento | Pagina | Stato |
|---|---|---|
| Paperclip (orchestratore di agenti) in Docker, agenti isolati via SSH | [tecnologie/paperclip/README.md](tecnologie/paperclip/README.md) | verificato (v2026.916.1, 2026-09) |
| Runner SSH isolato per agenti Codex | [tecnologie/paperclip/runner-ssh.md](tecnologie/paperclip/runner-ssh.md) | verificato |
| Artefatti di riferimento collaudati (runner, proxy di uscita) | [tecnologie/paperclip/riferimento/](tecnologie/paperclip/riferimento/README.md) | verificato |
| Test riutilizzabili per Paperclip e runner | [tecnologie/paperclip/test/](tecnologie/paperclip/test/README.md) | verificato |

## Soluzioni trasversali

| Argomento | Pagina |
|---|---|
| Reti Docker: cosa raggiunge un container e come limitare l'uscita | [trasversali/docker-reti-e-uscita.md](trasversali/docker-reti-e-uscita.md) |
| Segreti nei container senza esporli a `docker inspect` | [trasversali/segreti-nei-container.md](trasversali/segreti-nei-container.md) |
| Processi remoti che sopravvivono alla chiusura di SSH | [trasversali/ssh-processi-orfani.md](trasversali/ssh-processi-orfani.md) |
| Ubuntu: `lxc` installa LXD da solo | [trasversali/ubuntu-lxc-installa-lxd.md](trasversali/ubuntu-lxc-installa-lxd.md) |

## Esperimenti (compresi quelli falliti)

| Esperimento | Esito |
|---|---|
| [esperimenti/2026-09-paperclip-isolamento-agenti.md](esperimenti/2026-09-paperclip-isolamento-agenti.md) | sandbox di Codex nei container, runner SSH, pulizia, rete: cosa ha funzionato, cosa no, ipotesi smentite |

## Come si scrive una pagina

Modello: [_modello.md](_modello.md). Distinguere sempre: **verificato** (con prova e versione), **ipotesi**,
**smentito**. Una sola pagina per argomento; le altre rimandano con un collegamento relativo.
