# Gemini: correzione in corso — 11 ottobre 2026

Sulla VM Ubuntu 26.04.1 con Gemini CLI 0.63.0, i log kernel dimostrano due attachment AppArmor concorrenti per /usr/bin/bwrap: bwrap-userns-restrict di Ubuntu e ops-bwrap del bootstrap. Il processo resta unconfined e passa a unprivileged_userns, che nega setpcap, net_admin e uid_map.

Il bootstrap cercava i profili con grep su /etc/apparmor.d/*, incluse directory. Con pipefail l'errore di grep può far prendere il ramo che installa ops-bwrap anche quando esiste il profilo Ubuntu. Il controllo ora esamina solo file regolari, senza pipeline.

Gemini 0.63.0 contiene security.toolSandboxing (default false) e LinuxSandboxManager basato su bubblewrap. Il pacchetto ora imposta toolSandboxing=true, tools.sandbox=false e disableYoloMode=true, mantenendo le approvazioni. Il controllo gemini-sandbox-check.mjs esegue il motore della versione installata senza modello; una API interna non disponibile o una prova fallita blocca l'avvio. La verifica operativa del contesto usa una sola chiamata Gemini: la prova di isolamento deterministica è già fatta prima del login.

Riparazione eseguita dall'amministratore sulla VM: esito positivo. Il profilo gestito è conservato in /var/backups/ops-bwrap-070; resta caricato il profilo Ubuntu. La prova diretta del motore Gemini è riuscita: AGENTS.md, servizio SSH e journal reali leggibili; workspace scrivibile; home in sola lettura. Nessuna chiamata al modello. Il test ha creato un file .geminiignore vuoto, poi rimosso; il pacchetto ora ne distribuisce uno con esclusione .env e .env.*.

Verificato: sintassi del bootstrap e del controllo JavaScript, git diff --check, riparazione privilegiata, sandbox nativa Gemini sulla VM Ubuntu 26.04.1. Collaudo finale del codice del commit 34b6f1f, da una copia fissa: 313/313 su ubuntu:24.04 e 313/313 su ubuntu:26.04 (log ~/bootstrap-gemini-final-24.log e ~/bootstrap-gemini-final-26.log sul N100). Include installazioni reali in container, verifiche simulate degli agenti, idempotenza, aggiornamento, ripresa, integrità e controllo statico. Nessuna chiamata al modello. Le sandbox reali in container non sono dimostrate: la prova Gemini è quella separata sulla VM.

Giri precedenti: esclusi dalla validazione finale. Il primo ha rilevato il controllo di migrazione errato; una ripetizione è stata invalidata dall'aggiornamento del sorgente mentre Bash lo leggeva. Il giro finale usa lo snapshot immutabile del commit 34b6f1f, mai modificato durante i test.

Ancora da verificare: aggiornamento del pacchetto sulla VM, login Gemini con chiave reale, caricamento del contesto tramite modello e configurazione iniziale con ops-installa. Nessuna pubblicazione della nuova versione.
