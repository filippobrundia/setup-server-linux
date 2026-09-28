# egress-proxy — uscita controllata del runner (solo CONNECT 443 verso host ammessi, mai indirizzi privati).
FROM node:24-trixie-slim@sha256:8ec5d7557396cfe32d21c3f9c13072355ceab22b584578ca4bb28af31120cffe
COPY proxy.mjs /opt/egress-proxy/proxy.mjs
USER node
ENTRYPOINT ["node", "/opt/egress-proxy/proxy.mjs"]
