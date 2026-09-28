# Processi remoti che sopravvivono alla chiusura di SSH

**Stato:** verificato (OpenSSH 10.0p2, 2026-09).

- Un comando eseguito via SSH **senza terminale** (`ssh host comando`) non riceve un segnale di chiusura quando il
  client viene terminato (tempo scaduto, annullamento): il processo continua sul server, riassegnato al pid 1 del
  container, e tiene aperti i propri file.
- Riconoscimento collaudato: un processo è ancora collegato se tra i suoi antenati c'è un processo `sshd-session`
  (OpenSSH ≥ 9.8; con versioni precedenti un `sshd` diverso dal pid 1). Senza questo antenato e senza attività
  recente, il lavoro è abbandonato: terminare i processi (`TERM`, poi `KILL`) e rimuoverne i file.
  Implementazione: [runner-common.sh](../tecnologie/paperclip/riferimento/runner/runner-common.sh).
