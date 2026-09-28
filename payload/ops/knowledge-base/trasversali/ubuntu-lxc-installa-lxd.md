# Ubuntu: il comando `lxc` installa LXD da solo

**Stato:** verificato (Ubuntu 24.04, 2026-09).

Su Ubuntu senza LXD, `lxc` (per esempio `lxc list` per controllare se LXD c'è) attiva `lxd-installer`, che
**installa lo snap `lxd`** e può lasciare unit `lxd-installer@…` fallite. Per controllare usare `snap list lxd`
(sola lettura). Rimozione, se installato per errore e mai inizializzato: verificare che non esistano istanze,
storage o reti, poi `snap remove --purge lxd` e `systemctl reset-failed` sulle sole unit coinvolte.
