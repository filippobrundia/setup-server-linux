# ai-company runner — esecuzione isolata degli agenti di Paperclip via SSH (un container dedicato, non privilegiato).
# Nessun socket Docker, nessun segreto del server, nessuna porta pubblicata. Codex a versione fissata.
FROM node:24-trixie-slim@sha256:8ec5d7557396cfe32d21c3f9c13072355ceab22b584578ca4bb28af31120cffe
ARG CODEX_VERSION=0.155.1
RUN apt-get update \
  && apt-get install -y --no-install-recommends openssh-server tar ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && npm install --global --omit=dev --no-fund --no-audit "@openai/codex@${CODEX_VERSION}" \
  && npm cache clean --force \
  && codex --version \
  && useradd -m -u 1001 -s /bin/sh agent \
  && install -d -m 0755 /etc/runner /var/lib/runner-ssh
COPY sshd_config /etc/runner/sshd_config
COPY runner-common.sh /usr/local/lib/runner-common.sh
COPY runner-proxy.sh /etc/profile.d/runner-proxy.sh
COPY runner-session.sh /usr/local/bin/runner-session
COPY runner-janitor.sh /usr/local/bin/runner-janitor
COPY entrypoint.sh /usr/local/bin/runner-entrypoint
RUN chmod 0755 /usr/local/bin/runner-session /usr/local/bin/runner-janitor /usr/local/bin/runner-entrypoint \
  && chmod 0644 /etc/runner/sshd_config /usr/local/lib/runner-common.sh /etc/profile.d/runner-proxy.sh \
  && chown agent:agent /var/lib/runner-ssh
LABEL org.opencontainers.image.title="ai-company runner" org.opencontainers.image.description="Runner SSH isolato per gli agenti (Codex ${CODEX_VERSION})"
USER agent
ENTRYPOINT ["/usr/local/bin/runner-entrypoint"]
