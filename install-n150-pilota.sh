#!/usr/bin/env bash
# One-command, resumable setup for the physical N150 pilot.
# Pinned to Foundation 0.8.0-rc.5 and N150 Add-on v0.1.2.
set -Eeuo pipefail
export LC_ALL=C.UTF-8

readonly FOUNDATION_VERSION='0.8.0-rc.5'
readonly FOUNDATION_INSTALLER="https://raw.githubusercontent.com/filippobrundia/setup-server-linux/v${FOUNDATION_VERSION}/install.sh"
readonly KB_URL='https://github.com/filippobrundia/server-knowledge-base.git'
readonly ADDON_REPO='git@github.com:filippobrundia/N150-Addon.git'
readonly ADDON_COMMIT='cf28cb576ac37fb1d4aad8d6da8b6e7338f971a7'
readonly ADDON_DIR="$HOME/n150-addon"
readonly ADDON_KEY="$HOME/.ssh/n150-addon-ro"
readonly GITHUB_ED25519_FPR='SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU'

die() { printf 'STOP: %s\n' "$*" >&2; exit 1; }
note() { printf '\n== %s ==\n' "$*"; }

[[ $EUID -ne 0 ]] || die 'esegui come utente amministratore normale, non come root.'
[[ -r /etc/os-release ]] || die 'impossibile identificare il sistema operativo.'
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == ubuntu && ${VERSION:-} == *LTS* ]] || die 'questa procedura richiede Ubuntu.'
id -nG | tr ' ' '\n' | grep -qx sudo || die "l'utente corrente deve appartenere al gruppo sudo."
[[ ! -e /usr/local/sbin/servern100-maint ]] || die 'Questo launcher richiede il nuovo N150.'
setup_mode=--foundation
case ${1:-} in
  '') [[ $# == 0 ]] || die 'Uso: install-n150-pilota.sh [--vm]' ;;
  --vm)
    [[ $# == 1 ]] || die 'Uso: install-n150-pilota.sh [--vm]'
    setup_mode=--vm ;;
  *) die 'Uso: install-n150-pilota.sh [--vm]' ;;
esac
if [[ $setup_mode == --vm ]]; then
  systemd-detect-virt --vm --quiet || die '--vm richiede una macchina virtuale.'
else
  [[ $(systemd-detect-virt || true) == none ]] || die 'Su una VM usa --vm.'
  grep -Eq '^model name[[:space:]]*:.*\bN150\b' /proc/cpuinfo ||
    die 'Serve un Intel N150 fisico.'
fi
command -v curl >/dev/null || die 'curl manca: installa curl e ca-certificates, poi rilancia questo stesso comando.'
if ! command -v ssh-keygen >/dev/null || ! command -v git >/dev/null; then
  sudo apt-get update
  sudo apt-get install -y git openssh-client
fi
command -v ssh-keygen >/dev/null || die 'openssh-client non e disponibile.'
command -v git >/dev/null || die 'git non e disponibile.'

# Prepare the read-only deploy key before changing the Foundation.
install -d -m 0700 "$HOME/.ssh"
if [[ ! -s $ADDON_KEY ]]; then
  note 'Creo la chiave SSH dedicata, limitata in seguito alla lettura del repository N150-Addon'
  ssh-keygen -q -t ed25519 -N '' -C 'n150-addon-readonly' -f "$ADDON_KEY"
  chmod 0600 "$ADDON_KEY"
  chmod 0644 "$ADDON_KEY.pub"
  printf '\nAggiungi questa chiave pubblica come deploy key di sola lettura a filippobrundia/N150-Addon:\n\n'
  cat "$ADDON_KEY.pub"
  printf '\nPoi rilancia lo stesso comando. Foundation non e stata ancora avviata.\n'
  exit 20
fi
[[ -s "$ADDON_KEY.pub" ]] || die "manca la chiave pubblica $ADDON_KEY.pub; non rigenero ne sovrascrivo la chiave privata esistente."
chmod 0600 "$ADDON_KEY"

# Pin and verify GitHub's SSH host key before using the private repository.
known_hosts="$HOME/.ssh/known_hosts"
if ! ssh-keygen -F github.com -f "$known_hosts" 2>/dev/null | grep -q " ssh-ed25519 "; then
  keyscan=$(ssh-keyscan -T 15 -t ed25519 github.com 2>/dev/null || true)
  fingerprint=$(printf '%s\n' "$keyscan" | ssh-keygen -lf - 2>/dev/null | awk 'NR == 1 {print $2}')
  [[ -n $keyscan && $fingerprint == "$GITHUB_ED25519_FPR" ]] \
    || die "impronta SSH GitHub non verificata (ricevuta: ${fingerprint:-nessuna})."
  printf '%s\n' "$keyscan" >> "$known_hosts"
  chmod 0600 "$known_hosts"
fi
stored_fingerprint=$(ssh-keygen -F github.com -f "$known_hosts" | awk '$2 == "ssh-ed25519"' | ssh-keygen -lf - 2>/dev/null | awk 'NR == 1 {print $2}')
[[ $stored_fingerprint == "$GITHUB_ED25519_FPR" ]] || die "impronta GitHub in known_hosts non corrispondente ($stored_fingerprint)."
GIT_SSH_COMMAND="ssh -i $ADDON_KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o HostKeyAlgorithms=ssh-ed25519" \
  git ls-remote --exit-code "$ADDON_REPO" refs/heads/main >/dev/null \
  || { printf 'La chiave non legge il repository privato. Controlla che la chiave pubblica sia registrata come deploy key read-only:\n' >&2; cat "$ADDON_KEY.pub" >&2; printf 'Foundation non e stata avviata.\n' >&2; exit 21; }

readonly ADVANCEMENT='/srv/ops/docs/bootstrap/avanzamento.md'
installed_version_file='/srv/ops/.bootstrap/version'
foundation_status_complete() {
  [[ -r $ADVANCEMENT ]] && grep -q '^STATO: COMPLETATO FOUNDATION' "$ADVANCEMENT"
}

if foundation_status_complete; then
  [[ -r $installed_version_file ]] || die "Foundation version file missing; stop before add-on."
  installed_version=$(<"$installed_version_file")
  [[ $installed_version == "$FOUNDATION_VERSION" ]] \
    || die "Foundation $installed_version rilevata, attesa $FOUNDATION_VERSION. Non aggiorno automaticamente una Foundation completa."
  note "Foundation $FOUNDATION_VERSION gie completata; non la reinstallo"
elif [[ -x /usr/local/bin/configura-server && -r $ADVANCEMENT ]]; then
  if [[ -r $installed_version_file ]]; then
    installed_version=$(<"$installed_version_file")
    [[ $installed_version == "$FOUNDATION_VERSION" ]] \
      || die "Foundation $installed_version gie presente ma incompleta; non la aggiorno automaticamente a $FOUNDATION_VERSION."
  fi
  note 'Riprendo la configurazione Foundation gie avviata'
  /usr/local/bin/configura-server --profilo docker "$setup_mode" </dev/tty
  foundation_status_complete || die 'la Foundation resta incompleta. Risolvi il gate indicato e rilancia lo stesso comando.'
else
  note "Avvio Foundation $FOUNDATION_VERSION: Docker, Codex e Knowledge Base"
  curl -fsSL "$FOUNDATION_INSTALLER" | bash -s -- \
    --configura --profilo docker "$setup_mode" --agente codex --kb-url "$KB_URL"
  foundation_status_complete || die 'la Foundation non risulta completata. Dopo il riavvio o il gate richiesto, rilancia lo stesso comando.'
  installed_version=$(</srv/ops/.bootstrap/version)
  [[ $installed_version == "$FOUNDATION_VERSION" ]] \
    || die "installata Foundation $installed_version, attesa $FOUNDATION_VERSION."
fi

if [[ ! -d /srv/ops/knowledge-base/.git ]]; then
  /srv/ops/bin/kb collega --url "$KB_URL" </dev/tty
fi
[[ -d /srv/ops/knowledge-base/.git ]] || die "Knowledge Base non collegata."
/srv/ops/bin/kb sync --quiet --strict

# Clone the exact, previously verified add-on commit; do not track a moving branch.
if [[ -e $ADDON_DIR && ! -d $ADDON_DIR/.git ]]; then
  die "$ADDON_DIR esiste ma non e un clone Git; conservo i file e mi fermo."
fi
if [[ ! -d $ADDON_DIR/.git ]]; then
  note 'Scarico N150 Add-on al commit v0.1.2 collaudato'
  GIT_SSH_COMMAND="ssh -i $ADDON_KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o HostKeyAlgorithms=ssh-ed25519" \
    git clone "$ADDON_REPO" "$ADDON_DIR"
fi
[[ $(git -C "$ADDON_DIR" remote get-url origin) == "$ADDON_REPO" ]] \
  || die "il clone $ADDON_DIR ha un origin diverso; conservo il clone e mi fermo."
[[ -z $(git -C "$ADDON_DIR" status --porcelain) ]] \
  || die "il clone $ADDON_DIR contiene modifiche locali; conservo i file e mi fermo."
git -C "$ADDON_DIR" cat-file -e "${ADDON_COMMIT}^{commit}" \
  || die "il commit richiesto $ADDON_COMMIT non e disponibile nel clone."
git -C "$ADDON_DIR" checkout --detach "$ADDON_COMMIT"
[[ $(git -C "$ADDON_DIR" rev-parse HEAD) == "$ADDON_COMMIT" ]] \
  || die 'il clone non e al commit v0.1.2 previsto.'

note "Controllo e applico solo i documenti dell'add-on"
python3 "$ADDON_DIR/install.py" --check
python3 "$ADDON_DIR/install.py" --apply
python3 "$ADDON_DIR/install.py" --check

printf '\nSETUP DOCUMENTALE COMPLETATO. Foundation e add-on sono installati.\n'
printf 'Esito Foundation: %s\n' "$(grep -m1 '^STATO:' "$ADVANCEMENT")"
printf 'Resta da avviare Codex separatamente per il collaudo in sola lettura:\n'
printf '  codex --cd /srv/ops/ws/flint2\n'
printf 'Nessun firmware, router, Frigate o telecamera e stato modificato da questo launcher.\n'
