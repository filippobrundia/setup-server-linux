# Reti Docker: cosa raggiunge un container e come limitare l'uscita

**Stato:** verificato (Docker 29.8, Ubuntu 24.04 con UFW, 2026-09).

## Fatti misurati
- Da una rete Docker **con uscita** (bridge normale) un container raggiunge il router, i dispositivi della LAN e le
  porte dell'host **pubblicate da Docker** (per esempio un reverse proxy sulla 80) su tutti gli indirizzi dell'host:
  il NAT e le regole di Docker precedono UFW. Le porte dei servizi dell'host non pubblicati da Docker (SSH, Samba,
  servizi in rete `host`) restano filtrate da UFW.
- Da una rete **interna** (`internal: true`) un container non raggiunge nulla fuori dalla rete: né l'host (anche sul
  gateway della rete), né la LAN, né altri container, né Internet; i nomi esterni non si risolvono.

## Schema collaudato per un container che deve uscire solo verso pochi servizi
Container solo su reti interne + proxy dedicato su due reti (interna con il container, con uscita verso Internet)
che accetta solo `CONNECT` sulla 443 verso host ammessi e rifiuta IP diretti e destinazioni che risolvono in indirizzi
privati, locali o riservati. Il container usa `HTTPS_PROXY`. Artefatto: [proxy.mjs](../tecnologie/paperclip/riferimento/egress-proxy/proxy.mjs).
Il proxy stesso è su una rete che raggiunge la LAN: la protezione è nel suo codice.

## Come verificare
Da dentro il container: [probe.mjs](../tecnologie/paperclip/test/probe.mjs) verso indirizzi dell'host, gateway delle
reti Docker, router, altri container, Internet; [proxytest.mjs](../tecnologie/paperclip/test/proxytest.mjs) per il proxy.
Non modificare firewall o routing dell'host per ottenere la separazione.
