#!/usr/bin/env bash
# bootstrap.sh — prepara un Ubuntu Server appena installato per l'amministrazione con agenti.
#
#   sudo ./bootstrap.sh --admin UTENTE [--owner "Nome"] [--check]
#   sudo ./bootstrap.sh --admin UTENTE --knowledge-base-only [--check]
#       aggiorna SOLO la Knowledge Base: strumento /srv/ops/bin/kb, kb.conf, copia locale (e chiede di nuovo se
#       collegarla). Nessun pacchetto, agente, home o manutenzione; nessuna modifica operativa.
#   Knowledge Base FACOLTATIVA, repository scelto dall'utente (nessun predefinito): durante l'avvio il bootstrap chiede
#   "Vuoi collegare una Knowledge Base? [S/N]", poi l'URL HTTPS e, solo se serve, un token di lettura (input nascosto),
#   tramite "kb collega" come amministratore; la scelta resta in kb.conf e non viene richiesta di nuovo.
#   Opzioni: --no-kb (nessuna domanda: KB non configurata per scelta), --kb-url URL (URL HTTPS già scelto),
#   --kb-id NOME (nome tecnico e non sensibile del server nei record; predefinito l'hostname).
#   Compatibilità: --kb-remote URL SSH o percorso locale = collegamento con deploy key delle versioni precedenti.
#   Esito 4: tutto il resto completato, ma la Knowledge Base richiesta NON è stata collegata (nessun terminale per
#   le domande, oppure rete o autorizzazione nel collegamento con deploy key).
#
# Fa soltanto questo, ed è ripetibile e riprendibile:
#   1. pacchetti minimi per l'agente (git, curl, ca-certificates, gnupg, jq) e Node.js 22 da NodeSource
#      (chiave verificata);
#   2. /srv/ops: regole (AGENTS.md), adattatori, documenti, checklist, script, file di avanzamento; repository Git;
#   3. Claude Code per l'amministratore (npm, canale stable, autoaggiornamento disattivato);
#   4. adattatori nella home (funzioni in ~/.bash_aliases, ~/CLAUDE.md di solo rimando, impostazioni di Claude);
#   5. componenti della manutenzione installati con /srv/ops/maint/install-maint, NESSUNA unit abilitata.
# Non partiziona, non formatta, non tocca rete, SSH, firewall, utenti o servizi, non avvia timer, non riavvia.
# Prima di cambiare qualcosa controlla tutto: al primo conflitto (file esistente diverso e non installato da
# questo pacchetto) si ferma senza modifiche. --check mostra il piano senza modificare nulla.
# Il login personale di Claude Code lo completa l'amministratore al primo avvio di "claude".
set -euo pipefail
export LC_ALL=C.UTF-8
PKG=$(cd "$(dirname "$0")" && pwd)
PKG_VERSION=$(cat "$PKG/VERSION")
OPS=/srv/ops
LOG=/var/log/ops-bootstrap.log
# impronte del pacchetto per ops-installa: copia di root, non modificabile dall'amministratore (né dagli agenti)
REFDIR=/var/lib/ops-bootstrap
REF=$REFDIR/pacchetto.manifest
INSTALLA=/usr/local/sbin/ops-installa
NODE_MAJOR=22
NS_KEY=/usr/share/keyrings/nodesource.gpg
NS_KEY_URL=https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
NS_KEY_SHA256=7a96b125f721c99e07d3f45b279adbd6884ec4f3f06750f6b54df40cfae36836   # verificata il 2026-09-27
NS_KEY_FPR=6F71F525282841EEDAF851B42F59B5F99B1BE0B4
NS_SOURCES=/etc/apt/sources.list.d/nodesource.sources
NS_PIN=/etc/apt/preferences.d/nodejs
MARK_BEGIN='# >>> ops: strumenti di amministrazione'
MARK_END='# <<< ops <<<'
BASE_PKGS="git curl ca-certificates gnupg jq openssh-client"
GITHUB_ED25519_FPR=SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU   # pubblicata da GitHub (api.github.com/meta)

ADMIN=${SUDO_USER:-}; OWNER=""; CHECK=0; KBONLY=0; KB_REMOTE=""; KB_ID=""; NO_KB=0
while [ $# -gt 0 ]; do
  case $1 in
    --admin) ADMIN=${2:-}; shift 2 ;;
    --owner) OWNER=${2:-}; shift 2 ;;
    --check) CHECK=1; shift ;;
    --knowledge-base-only) KBONLY=1; shift ;;
    --kb-remote|--kb-url) KB_REMOTE=${2:-}; shift 2 ;;
    --no-kb) NO_KB=1; shift ;;
    --kb-id) KB_ID=${2:-}; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "opzione sconosciuta: $1" >&2; exit 2 ;;
  esac
done

TS=$(date -u +%Y%m%d-%H%M%S); TODAY=$(date -u +%F)
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
CONFLICTS=(); PLAN=()
log()  { local m; m="$(date -u '+%F %T') $*"; echo "$m"; [ "$CHECK" = 1 ] || echo "$m" >> "$LOG"; }
die()  { echo "STOP: $*" >&2; [ "$CHECK" = 1 ] || echo "$(date -u '+%F %T') STOP: $*" >> "$LOG"; exit 3; }
conflict() { CONFLICTS+=("$*"); }
plan()     { PLAN+=("$*"); }
sha()  { sha256sum "$1" | cut -d' ' -f1; }
as_admin() { (cd "$AHOME" && runuser -u "$ADMIN" -- env HOME="$AHOME" USER="$ADMIN" \
               PATH="$AHOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin" "$@"); }

# ============================================================== PRECHECK (nessuna modifica)
[ "$(id -u)" = 0 ] || die "va eseguito con sudo"
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = ubuntu ] || die "sistema non Ubuntu (${ID:-?})"
[[ "${VERSION:-}" == *LTS* ]] || die "serve una release LTS di Ubuntu (trovata: ${VERSION:-?})"
[[ "${VERSION_ID:-}" =~ ^[0-9]+\.[0-9]+$ ]] && [[ "${VERSION_CODENAME:-}" =~ ^[a-z]+$ ]] || die "versione Ubuntu non riconosciuta"

[[ "$ADMIN" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "serve --admin UTENTE (nome valido), oppure eseguire con sudo dall'utente amministratore"
AUID=$(id -u "$ADMIN" 2>/dev/null) || die "utente $ADMIN inesistente (crearlo con l'installer di Ubuntu)"
[ "$AUID" -ge 1000 ] || die "$ADMIN non è un utente normale (uid $AUID)"
groups_of=" $(id -nG "$ADMIN") "; [[ "$groups_of" == *" sudo "* ]] || die "$ADMIN non è nel gruppo sudo"
AHOME=$(getent passwd "$ADMIN" | cut -d: -f6)
[ -d "$AHOME" ] || die "home di $ADMIN assente ($AHOME)"
if [ -z "$OWNER" ]; then OWNER=$(getent passwd "$ADMIN" | cut -d: -f5 | cut -d, -f1 | awk '{print $1}'); fi
[ -n "$OWNER" ] || OWNER=$ADMIN
[[ "$OWNER" =~ ^[[:alpha:]][[:alnum:]\ \'._-]{0,40}$ ]] || die "--owner non valido: usare lettere, cifre e spazi"
HOST=$(hostname -s)
[ -n "$KB_ID" ] || KB_ID=$HOST
[[ "$KB_ID" =~ ^[a-z0-9][a-z0-9-]{0,23}$ ]] || die "--kb-id non valido ($KB_ID): minuscole, cifre e trattini, massimo 24"
[ -z "$KB_REMOTE" ] || [[ "$KB_REMOTE" =~ ^[A-Za-z0-9@:/._~+-]+$ ]] || die "--kb-url/--kb-remote non valido"
[[ "$KB_REMOTE" != https://*@* ]] || die "--kb-url: nessuna credenziale nell'URL (il token si inserisce quando richiesto)"
[ "$NO_KB" = 0 ] || [ -z "$KB_REMOTE" ] || die "--no-kb e --kb-url sono alternativi"
kb_legacy() { [ -n "$1" ] && [[ "$1" != https://* ]]; }   # SSH o percorso locale: deploy key (versioni precedenti)
KB_SSHKEY_RENDER=""; kb_legacy "$KB_REMOTE" && KB_SSHKEY_RENDER="$AHOME/.ssh/kb_deploy"
[[ "$HOST" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || die "hostname non valido ($HOST): impostarlo prima con hostnamectl"

# Mai sul server di origine o su una /srv/ops che non è nostra.
[ ! -e /usr/local/sbin/servern100-maint ] || die "questa macchina ha la manutenzione di servern100: il pacchetto non si applica qui"
if [ -e "$OPS" ] && [ ! -f "$OPS/.bootstrap/manifest" ]; then
  die "$OPS esiste e non è stato creato da questo pacchetto: nessuna modifica"
fi
if [ "$KBONLY" = 1 ] && [ ! -f "$OPS/.bootstrap/manifest" ]; then
  die "--knowledge-base-only richiede una /srv/ops già preparata da questo pacchetto"
fi

for f in payload/ops/AGENTS.md.tmpl payload/ops/maint/install-maint payload/ops/maint/ops-maint payload/home/bash_aliases.block; do
  [ -f "$PKG/$f" ] || die "pacchetto incompleto: manca $f"
done
for f in "$PKG"/payload/ops/bin/* "$PKG/payload/ops/maint/ops-maint" "$PKG/payload/ops/maint/install-maint" "$PKG"/payload/ops/docs/bootstrap/*.sh "$PKG/payload/ops/docs/bootstrap/ops-installa"; do
  bash -n "$f" || die "errore di sintassi in $f"
done

log "== setup-server-linux $PKG_VERSION su $HOST (Ubuntu $VERSION_ID $VERSION_CODENAME), amministratore $ADMIN ($OWNER)$([ "$CHECK" = 1 ] && echo ', SOLO CONTROLLO')"

# --- Rendering del payload in una cartella temporanea (solo i segnaposto noti) ---
render() {  # $1 sorgente → $2 destinazione
  local s; s=$(cat "$1")
  s=${s//@@HOST@@/$HOST}; s=${s//@@ADMIN@@/$ADMIN}; s=${s//@@OWNER@@/$OWNER}
  s=${s//@@DATE@@/$TODAY}; s=${s//@@PKG_VERSION@@/$PKG_VERSION}
  s=${s//@@KB_REMOTE@@/$KB_REMOTE}; s=${s//@@KB_SERVER_ID@@/$KB_ID}; s=${s//@@AHOME@@/$AHOME}
  s=${s//@@KB_SSH_KEY@@/$KB_SSHKEY_RENDER}
  printf '%s\n' "$s" > "$2"
}
seed_file() {  # file che l'agente compila e aggiorna: creati una volta, mai sovrascritti
  case $1 in
    AGENTS.md|STATUS.md|CHANGELOG.md|host.conf|docs/bootstrap/avanzamento.md) return 0 ;;
    docs/overview.md|docs/system.md|docs/network.md|docs/storage-backup.md|docs/security.md) return 0 ;;
    docs/decisions.md|docs/future-improvements.md|kb.conf) return 0 ;;
  esac
  return 1
}
mkdir -p "$STAGE/ops"
( cd "$PKG/payload/ops" && find . -type f | sed 's|^\./||' | sort ) > "$STAGE/src.list"
while IFS= read -r rel; do
  out=$rel
  # I modelli sotto maint/ li completa install-maint al momento dell'installazione: si copiano come sono.
  if [[ "$rel" == *.tmpl && "$rel" != maint/* ]]; then out=${rel%.tmpl}; fi
  mkdir -p "$STAGE/ops/$(dirname "$out")"
  if [ "$out" != "$rel" ]; then render "$PKG/payload/ops/$rel" "$STAGE/ops/$out"; else cp "$PKG/payload/ops/$rel" "$STAGE/ops/$out"; fi
  echo "$out" >> "$STAGE/out.list"
done < "$STAGE/src.list"
if [ "$KBONLY" = 1 ]; then grep -xE 'bin/kb|kb\.conf|\.gitignore' "$STAGE/out.list" > "$STAGE/kb.list" || true; mv "$STAGE/kb.list" "$STAGE/out.list"; fi

# --- Piano per /srv/ops ---
declare -A OLD=()
if [ -f "$OPS/.bootstrap/manifest" ]; then
  while read -r h p _; do OLD[$p]=$h; done < "$OPS/.bootstrap/manifest"
fi
declare -A ACTION=()
while IFS= read -r rel; do
  dst=$OPS/$rel
  if [ ! -e "$dst" ]; then ACTION[$rel]=create; plan "crea $dst"
  elif [ -L "$dst" ] || [ ! -f "$dst" ]; then conflict "$dst non è un file regolare"
  elif cmp -s "$STAGE/ops/$rel" "$dst"; then ACTION[$rel]=same
  elif seed_file "$rel"; then ACTION[$rel]=keep
  elif [ -n "${OLD[$rel]:-}" ] && [ "$(sha "$dst")" = "${OLD[$rel]}" ]; then ACTION[$rel]=update; plan "aggiorna $dst (versione precedente del pacchetto, non modificata)"
  else conflict "$dst modificato rispetto al pacchetto: confrontare con $PKG/payload/ops/$rel"; fi
done < "$STAGE/out.list"

if [ "$KBONLY" = 0 ]; then   # --- controlli non necessari per il solo aggiornamento della Knowledge Base ---
# --- Home dell'amministratore ---
render "$PKG/payload/home/CLAUDE.md.tmpl" "$STAGE/home-CLAUDE.md"
if [ -e "$AHOME/CLAUDE.md" ]; then
  cmp -s "$STAGE/home-CLAUDE.md" "$AHOME/CLAUDE.md" || conflict "$AHOME/CLAUDE.md esiste con un contenuto diverso"
else plan "crea $AHOME/CLAUDE.md (solo rimando a /srv/ops/AGENTS.md)"; fi
BA=$AHOME/.bash_aliases
if [ -f "$BA" ] && grep -qF "$MARK_BEGIN" "$BA"; then
  sed -n "\|^$MARK_BEGIN|,\|^$MARK_END|p" "$BA" | cmp -s - "$PKG/payload/home/bash_aliases.block" \
    || conflict "$BA contiene un blocco ops diverso da quello del pacchetto"
elif [ -f "$BA" ] && grep -qE '^[[:space:]]*(alias[[:space:]]+)?(claude|codex|gemini|agy)[[:space:]]*(\(\)|=)' "$BA"; then
  conflict "$BA definisce già claude/codex/gemini/agy fuori dal blocco del pacchetto"
else plan "aggiunge il blocco ops a $BA"; fi
grep -qs 'bash_aliases' "$AHOME/.bashrc" || plan "ATTENZIONE: $AHOME/.bashrc non carica ~/.bash_aliases (non viene modificato)"
CS=$AHOME/.claude/settings.json
if [ -e "$CS" ]; then
  if ! jq -e . "$CS" >/dev/null 2>&1; then
    if command -v jq >/dev/null; then conflict "$CS non è JSON valido"; else plan "controllo di $CS dopo l'installazione di jq"; fi
  else
    jq -e '(.env.DISABLE_AUTOUPDATER // "1") == "1" and (.autoUpdatesChannel // "stable") == "stable"' "$CS" >/dev/null \
      || conflict "$CS ha impostazioni di aggiornamento diverse da DISABLE_AUTOUPDATER=1 / stable"
    grep -qE '"(bypassPermissions|dangerously[A-Za-z]*)"' "$CS" && conflict "$CS contiene una modalità che salta le approvazioni"
  fi
fi
NPMRC=$AHOME/.npmrc
if [ -f "$NPMRC" ] && grep -q '^prefix=' "$NPMRC"; then
  p=$(sed -n 's/^prefix=//p' "$NPMRC" | head -1)
  [[ $p == "$AHOME/.npm-global" || $p == \~/.npm-global || $p == '${HOME}/.npm-global' ]] || conflict "$NPMRC usa prefix=$p (atteso $AHOME/.npm-global)"
fi
if [ -x "$AHOME/.local/bin/claude" ] || [ -L "$AHOME/.local/bin/claude" ]; then
  conflict "Claude Code è già installato con l'installatore nativo ($AHOME/.local/bin/claude): cli-update gestisce l'installazione npm"
fi

# --- Node.js / NodeSource ---
if [ -e "$NS_KEY" ] && [ "$(sha "$NS_KEY")" != "$NS_KEY_SHA256" ]; then conflict "$NS_KEY diversa dalla chiave NodeSource verificata"; fi
NS_WANT="Types: deb
URIs: https://deb.nodesource.com/node_${NODE_MAJOR}.x
Suites: nodistro
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: $NS_KEY"
if [ -e "$NS_SOURCES" ]; then [ "$(cat "$NS_SOURCES")" = "$NS_WANT" ] || conflict "$NS_SOURCES esiste con un contenuto diverso (serve node_${NODE_MAJOR}.x)"
else plan "repository NodeSource node_${NODE_MAJOR}.x ($NS_SOURCES)"; fi
for f in /etc/apt/sources.list.d/*; do
  [ "$f" = "$NS_SOURCES" ] && continue
  grep -qs 'deb.nodesource.com' "$f" && conflict "$f definisce già un repository NodeSource"
done
NS_PIN_WANT="Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 600"
if [ -e "$NS_PIN" ]; then [ "$(cat "$NS_PIN")" = "$NS_PIN_WANT" ] || conflict "$NS_PIN esiste con un contenuto diverso"; fi
if dpkg-query -W -f='${db:Status-Abbrev}' nodejs 2>/dev/null | grep -q '^ii'; then
  nv=$(dpkg-query -W -f='${Version}' nodejs); nmaj=${nv%%.*}; nmaj=${nmaj#*:}
  [ "$nmaj" -ge "$NODE_MAJOR" ] 2>/dev/null || conflict "nodejs $nv già installato (serve >= $NODE_MAJOR): va sostituito con una decisione esplicita"
else plan "installa nodejs ${NODE_MAJOR}.x"; fi

# --- Manutenzione: i file di destinazione devono essere assenti o nostri ---
for f in /usr/local/sbin/ops-maint /etc/tmpfiles.d/ops-maint.conf /etc/systemd/system/ops-maint-window.service \
         /etc/systemd/system/ops-maint-window.timer /etc/systemd/system/ops-postboot.service \
         /etc/systemd/system/ops-cli-update.service /etc/systemd/system/ops-cli-update.timer; do
  if [ -e "$f" ] && ! head -n 4 "$f" | grep -qE '(ops-maint|Description=ops:)'; then conflict "$f esiste e non è della manutenzione del pacchetto"; fi
done
if [ -e /etc/ops-maint.conf ]; then
  a=$(awk 'index($0,"ADMIN=")==1 {print substr($0,7); exit}' /etc/ops-maint.conf)
  [ "$a" = "$ADMIN" ] || conflict "/etc/ops-maint.conf indica ADMIN=$a"
fi
for u in ops-maint-window.timer ops-cli-update.timer; do
  if [ -d /run/systemd/system ] && systemctl is-enabled --quiet "$u" 2>/dev/null; then plan "nota: $u è già abilitato (lasciato com'è)"; fi
done
# --- Comando unico della configurazione iniziale ---
if [ -e "$INSTALLA" ] && ! head -n 4 "$INSTALLA" | grep -q 'ops-installa'; then conflict "$INSTALLA esiste e non è del pacchetto"; fi
if [ -e "$REFDIR" ]; then
  [ -d "$REFDIR" ] && [ ! -L "$REFDIR" ] && [ "$(stat -c '%U:%G %a' "$REFDIR")" = "root:root 700" ] || conflict "$REFDIR esiste e non è una cartella root 0700"
fi

fi
# --- Esito del controllo ---
[ "${#PLAN[@]}" -gt 0 ] && printf '  piano: %s\n' "${PLAN[@]}"
if [ "${#CONFLICTS[@]}" -gt 0 ]; then
  printf '  CONFLITTO: %s\n' "${CONFLICTS[@]}" >&2
  die "${#CONFLICTS[@]} conflitti: nessuna modifica eseguita. Risolverli (o spostare i file) e rieseguire."
fi
if [ "$CHECK" = 1 ]; then echo "Controllo superato: nessuna modifica eseguita (--check)."; exit 0; fi
touch "$LOG"; chmod 0640 "$LOG"

# ============================================================== MODIFICA
apt_install() {  # simulazione prima: nessuna rimozione ammessa
  local sim
  sim=$(apt-get -s install --no-install-recommends "$@" 2>&1) || die "simulazione APT non riuscita: $(tail -1 <<< "$sim")"
  grep -q '^Remv' <<< "$sim" && die "l'installazione di $* rimuoverebbe pacchetti: stop"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -o DPkg::Lock::Timeout=600 "$@" >> "$LOG" 2>&1 \
    || die "apt-get install $* non riuscito (dettagli in $LOG)"
}
missing_pkgs() { local p; for p in "$@"; do dpkg-query -W -f='${db:Status-Abbrev}' "$p" 2>/dev/null | grep -q '^ii' || echo "$p"; done; }

if [ "$KBONLY" = 0 ]; then
log "== 1/5 pacchetti di base e Node.js $NODE_MAJOR"
mapfile -t miss < <(missing_pkgs $BASE_PKGS)
if [ "${#miss[@]}" -gt 0 ]; then
  apt-get -o DPkg::Lock::Timeout=600 update >> "$LOG" 2>&1 || die "apt-get update non riuscito (dettagli in $LOG)"
  apt_install "${miss[@]}"; log "  installati: ${miss[*]}"
else log "  già presenti: $BASE_PKGS"; fi
if [ ! -e "$NS_KEY" ]; then
  curl -fsSL -m 60 "$NS_KEY_URL" | gpg --dearmor > "$STAGE/ns.gpg"
  [ "$(sha "$STAGE/ns.gpg")" = "$NS_KEY_SHA256" ] || die "chiave NodeSource scaricata diversa da quella verificata"
  keys=$(gpg --show-keys --with-colons "$STAGE/ns.gpg" 2>/dev/null); grep -q "fpr:::::::::$NS_KEY_FPR:" <<< "$keys" || die "impronta della chiave NodeSource inattesa"
  install -o root -g root -m 0644 "$STAGE/ns.gpg" "$NS_KEY"; log "  chiave NodeSource installata (verificata)"
fi
[ -e "$NS_SOURCES" ] || { printf '%s\n' "$NS_WANT" > "$NS_SOURCES"; chmod 0644 "$NS_SOURCES"; log "  creato $NS_SOURCES"; }
[ -e "$NS_PIN" ] || { printf '%s\n' "$NS_PIN_WANT" > "$NS_PIN"; chmod 0644 "$NS_PIN"; log "  creato $NS_PIN"; }
if ! dpkg-query -W -f='${db:Status-Abbrev}' nodejs 2>/dev/null | grep -q '^ii'; then
  apt-get -o DPkg::Lock::Timeout=600 update >> "$LOG" 2>&1 || die "apt-get update non riuscito (dettagli in $LOG)"
  pol=$(apt-cache policy nodejs); grep -q 'deb.nodesource.com' <<< "$pol" || die "nodejs non disponibile dal repository NodeSource"
  apt_install nodejs
fi
nv=$(node --version 2>/dev/null || true); nmaj=${nv#v}; nmaj=${nmaj%%.*}
[ "${nmaj:-0}" -ge "$NODE_MAJOR" ] 2>/dev/null || die "Node.js $NODE_MAJOR non disponibile dopo l'installazione (trovato: ${nv:-nessuno})"
log "  node $nv"

fi

log "== 2/5 /srv/ops$([ "$KBONLY" = 1 ] && echo ' (solo strumento e configurazione della knowledge base)')"
install -d -o "$ADMIN" -g "$ADMIN" -m 0775 "$OPS"
while IFS= read -r rel; do
  case ${ACTION[$rel]} in
    create|update)
      mode=0644; case $rel in bin/*|maint/ops-maint|maint/install-maint) mode=0755 ;; esac
      install -d -o "$ADMIN" -g "$ADMIN" -m 0775 "$OPS/$(dirname "$rel")"
      install -o "$ADMIN" -g "$ADMIN" -m "$mode" "$STAGE/ops/$rel" "$OPS/$rel"
      log "  ${ACTION[$rel]}: $rel" ;;
  esac
done < "$STAGE/out.list"
install -d -o "$ADMIN" -g "$ADMIN" -m 0775 "$OPS/.bootstrap"
# Impronte dei file distribuiti: servono a riconoscere, al prossimo avvio, i file modificati localmente.
# Manifest unito: le voci dei file non trattati restano; per i file conservati resta l'impronta installata.
{ while IFS= read -r rel; do
    echo "$(sha "$STAGE/ops/$rel")  $rel"
  done < "$STAGE/out.list"
  if [ "$KBONLY" = 1 ]; then for k in "${!OLD[@]}"; do case $k in knowledge-base/*) continue ;; esac; grep -qxF "$k" "$STAGE/out.list" || echo "${OLD[$k]}  $k"; done; fi
} | sort -k2 > "$STAGE/manifest"
install -o "$ADMIN" -g "$ADMIN" -m 0644 "$STAGE/manifest" "$OPS/.bootstrap/manifest"
# Copia di root delle impronte (riferimento di ops-installa). Con --knowledge-base-only si aggiornano solo le voci
# trattate e le altre restano quelle della copia di root (mai quelle del manifest dell'amministratore).
if [ "$KBONLY" = 0 ]; then
  install -d -o root -g root -m 0700 "$REFDIR"; install -o root -g root -m 0644 "$STAGE/manifest" "$REF"
elif [ -f "$REF" ]; then
  { awk 'NR == FNR {skip[$1] = 1; next} !($2 in skip)' "$STAGE/out.list" "$REF" 2>/dev/null
    while IFS= read -r rel; do echo "$(sha "$STAGE/ops/$rel")  $rel"; done < "$STAGE/out.list"; } | sort -k2 > "$STAGE/ref"
  install -o root -g root -m 0644 "$STAGE/ref" "$REF"
fi
if [ "$KBONLY" = 1 ]; then echo "$PKG_VERSION" > "$STAGE/kbversion"; install -o "$ADMIN" -g "$ADMIN" -m 0644 "$STAGE/kbversion" "$OPS/.bootstrap/knowledge-base-version"
else echo "$PKG_VERSION" > "$STAGE/version"; install -o "$ADMIN" -g "$ADMIN" -m 0644 "$STAGE/version" "$OPS/.bootstrap/version"; fi
# --- Knowledge Base FACOLTATIVA (repository separato scelto dall'utente; copia locale non versionata nella foundation) ---
KB_OK=0; KB_STATE=""
kb_conf_val() { awk -v k="$1" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2); sub(/[ \t]+#.*$/, "", v); gsub(/"/, "", v); print v; exit }' "$OPS/kb.conf" 2>/dev/null; }
kb_ready() {  # copia presente e verificata con kb status
  local st
  [ -d "$OPS/knowledge-base/.git" ] || return 1
  st=$(as_admin "$OPS/bin/kb" status) || { log "  ATTENZIONE: kb status non riuscito (rc=$?): Knowledge Base NON verificata"; return 1; }
  KB_OK=1; KB_STATE=ok; log "  Knowledge Base disponibile: ${st%%$'\n'*}"
}
kb_legacy_setup() {  # collegamento SSH con deploy key, come nelle versioni precedenti (installazioni esistenti)
  local remote=$1 key="$AHOME/.ssh/kb_deploy" kh="$AHOME/.ssh/known_hosts" rc
  command -v ssh-keygen >/dev/null || { log "  ssh-keygen assente (openssh-client)"; return 1; }
  as_admin install -d -m 0700 "$AHOME/.ssh"
  if [ ! -f "$key" ]; then as_admin ssh-keygen -q -t ed25519 -N '' -C "kb-deploy $KB_ID" -f "$key"; log "  deploy key del server creata: $key"; fi
  if [[ "$remote" == git@github.com:* || "$remote" == ssh://git@github.com/* ]] && ! as_admin ssh-keygen -F github.com -f "$kh" >/dev/null 2>&1; then
    local line fpr; line=$(ssh-keyscan -T 15 -t ed25519 github.com 2>/dev/null); fpr=$(ssh-keygen -lf - <<< "$line" 2>/dev/null | awk '{print $2}')
    if [ -n "$line" ] && [ "$fpr" = "$GITHUB_ED25519_FPR" ]; then printf '%s\n' "$line" | as_admin tee -a "$kh" >/dev/null; log "  chiave host di GitHub verificata ($fpr)"
    else log "  chiave host di GitHub non verificabile (rete assente o impronta diversa: $fpr)"; fi
  fi
  as_admin "$OPS/bin/kb" init; rc=$?
  if [ "$rc" = 0 ] && kb_ready; then
    if as_admin sh -c 'command -v crontab' >/dev/null; then as_admin "$OPS/bin/kb" schedule on | sed 's/^/  /' | tee -a "$LOG"
    else log "  ATTENZIONE: cron assente, sincronizzazione periodica non configurata (usare kb sync a inizio lavoro)"; fi
    return 0
  fi
  KB_STATE=fallita
  log "  KNOWLEDGE BASE NON RECUPERATA: fase NON completata."
  log "  Registrare la chiave pubblica del server come deploy key del repository:"
  log "    $(cat "$key.pub")"
  log "  poi, come $ADMIN: /srv/ops/bin/kb init   (oppure: sudo bootstrap.sh --admin $ADMIN --knowledge-base-only)"
  return 1
}
kb_setup() {
  local cur scelta args=() rc=0
  log "== Knowledge Base (facoltativa)"
  if [ -e "$OPS/knowledge-base" ] && [ ! -d "$OPS/knowledge-base/.git" ]; then   # copia incorporata della 0.2.0
    mv "$OPS/knowledge-base" "$OPS/knowledge-base.v0.2.0-$TS"; chown -R "$ADMIN:$ADMIN" "$OPS/knowledge-base.v0.2.0-$TS"
    log "  copia della Knowledge Base 0.2.0 spostata (conservata): $OPS/knowledge-base.v0.2.0-$TS"
  fi
  cur=$(kb_conf_val KB_REMOTE); scelta=$(kb_conf_val KB_SCELTA)
  if [ -d "$OPS/knowledge-base/.git" ] && [ -n "$cur" ]; then   # già collegata (HTTPS o deploy key): solo sincronizzazione
    as_admin "$OPS/bin/kb" sync || true; kb_ready || KB_STATE=fallita; return 0
  fi
  if kb_legacy "$cur"; then kb_legacy_setup "$cur"; return; fi
  if [ "$NO_KB" = 1 ]; then as_admin "$OPS/bin/kb" collega --no | sed 's/^/  /' | tee -a "$LOG"; KB_STATE=scelta; return 0; fi
  if [ "$scelta" = no ] && [ "$KBONLY" = 0 ] && [ -z "$KB_REMOTE" ]; then
    log "  KB non configurata per scelta (registrata in kb.conf; per collegarla: /srv/ops/bin/kb collega)"; KB_STATE=scelta; return 0
  fi
  if [ -n "$KB_REMOTE" ]; then args=(--url "$KB_REMOTE"); elif [ -n "$cur" ]; then args=(--url "$cur"); fi
  # domande al terminale dell'amministratore (input del token nascosto, mai nei log); nessuna ripetizione della foundation
  as_admin env ${KB_TTY:+KB_TTY="$KB_TTY"} "$OPS/bin/kb" collega "${args[@]}" || rc=$?
  if [ "$rc" = 0 ] && [ "$(kb_conf_val KB_SCELTA)" = no ]; then log "  KB non configurata per scelta"; KB_STATE=scelta; return 0; fi
  if [ "$rc" = 0 ] && kb_ready; then return 0; fi
  KB_STATE=fallita
  log "  Knowledge Base richiesta ma NON collegata (codice $rc). Per collegarla in seguito, come $ADMIN da un terminale:"
  log "    /srv/ops/bin/kb collega"
  return 1
}
kb_setup || true

if [ ! -d "$OPS/.git" ]; then as_admin git -C "$OPS" init -q -b main; log "  repository Git creato"; fi
if ! as_admin git config --global user.email >/dev/null 2>&1 && ! as_admin git -C "$OPS" config user.email >/dev/null 2>&1; then
  as_admin git -C "$OPS" config user.name "$OWNER"; as_admin git -C "$OPS" config user.email "$ADMIN@$HOST"
  log "  identità Git locale del repository: $OWNER <$ADMIN@$HOST>"
fi
as_admin git -C "$OPS" add -A
if as_admin git -C "$OPS" diff --cached --quiet; then log "  nessuna modifica da registrare in Git"
else as_admin git -C "$OPS" commit -q -m "bootstrap: $([ "$KBONLY" = 1 ] && echo 'knowledge base aggiornata da' || echo 'pacchetto') setup-server-linux $PKG_VERSION"; log "  commit: $(as_admin git -C "$OPS" log --oneline -1)"; fi

if [ "$KBONLY" = 1 ]; then
  log "== VERIFY"
  [ -z "$(as_admin git -C "$OPS" status --porcelain)" ] && log "  /srv/ops: repository pulito" || die "/srv/ops: modifiche non registrate"
  [ "$KB_STATE" != fallita ] || { log "Knowledge Base NON collegata: vedere le istruzioni sopra."; exit 4; }
  log "Fatto: solo la Knowledge Base è stata aggiornata ($([ "$KB_OK" = 1 ] && echo collegata || echo 'non configurata per scelta')); nessuna modifica operativa."
  exit 0
fi

log "== 3/5 Claude Code per $ADMIN"
if [ ! -f "$NPMRC" ] || ! grep -q '^prefix=' "$NPMRC"; then
  echo "prefix=$AHOME/.npm-global" >> "$NPMRC"; chown "$ADMIN:$ADMIN" "$NPMRC"; log "  npm: prefix utente $AHOME/.npm-global"
fi
as_admin mkdir -p "$AHOME/.npm-global"
if as_admin npm ls -g --depth=0 @anthropic-ai/claude-code >/dev/null 2>&1; then
  log "  già installato: $(as_admin claude --version 2>/dev/null | head -1)"
else
  as_admin npm install -g --no-fund --no-audit @anthropic-ai/claude-code@stable >> "$LOG" 2>&1 || die "installazione di Claude Code non riuscita (dettagli in $LOG)"
  log "  installato: $(as_admin claude --version 2>/dev/null | head -1)"
fi

log "== 4/5 adattatori nella home"
if [ ! -e "$AHOME/CLAUDE.md" ]; then install -o "$ADMIN" -g "$ADMIN" -m 0644 "$STAGE/home-CLAUDE.md" "$AHOME/CLAUDE.md"; log "  creato ~/CLAUDE.md"; fi
if ! { [ -f "$BA" ] && grep -qF "$MARK_BEGIN" "$BA"; }; then
  [ -f "$BA" ] && cp -p "$BA" "$BA.bak-$TS"
  { [ -s "$BA" ] && echo; cat "$PKG/payload/home/bash_aliases.block"; } >> "$BA"; chown "$ADMIN:$ADMIN" "$BA"
  log "  blocco ops aggiunto a ~/.bash_aliases"
fi
as_admin install -d -m 0700 "$AHOME/.claude"
if [ -e "$CS" ]; then
  jq -e '.env.DISABLE_AUTOUPDATER == "1" and .autoUpdatesChannel == "stable"' "$CS" >/dev/null 2>&1 \
    || { cp -p "$CS" "$CS.bak-$TS"; jq '.env.DISABLE_AUTOUPDATER = "1" | .autoUpdatesChannel = "stable"' "$CS.bak-$TS" > "$STAGE/cs.json"
         install -o "$ADMIN" -g "$ADMIN" -m 0600 "$STAGE/cs.json" "$CS"; log "  impostazioni di Claude integrate (copia $CS.bak-$TS)"; }
else
  install -o "$ADMIN" -g "$ADMIN" -m 0600 "$PKG/payload/home/claude-settings.json" "$CS"; log "  creato ~/.claude/settings.json"
fi

log "== 5/5 manutenzione (installata, non attivata) e comando unico ops-installa"
"$OPS/maint/install-maint" install --admin "$ADMIN" | sed 's/^/  /' | tee -a "$LOG"
if ! cmp -s "$STAGE/ops/docs/bootstrap/ops-installa" "$INSTALLA"; then
  install -d -m 0755 "$(dirname "$INSTALLA")"
  install -o root -g root -m 0755 "$STAGE/ops/docs/bootstrap/ops-installa" "$INSTALLA"; log "  installato: $INSTALLA"
fi

# ============================================================== VERIFY
log "== VERIFY"
v_ok=1
[ -z "$(as_admin git -C "$OPS" status --porcelain)" ] && log "  /srv/ops: repository pulito" || { log "  /srv/ops: modifiche non registrate"; v_ok=0; }
grep -qx 'STATO: IN CORSO' "$OPS/docs/bootstrap/avanzamento.md" && log "  avanzamento: configurazione iniziale IN CORSO" \
  || log "  avanzamento: $(grep -m1 '^STATO:' "$OPS/docs/bootstrap/avanzamento.md")"
as_admin claude --version >/dev/null 2>&1 && log "  claude: $(as_admin claude --version | head -1)" || { log "  claude non eseguibile"; v_ok=0; }
as_admin bash -ic 'type -t claude' 2>/dev/null | grep -qx function && log "  funzione claude attiva nelle shell interattive" \
  || log "  ATTENZIONE: la funzione claude non risulta nelle shell interattive (controllare ~/.bashrc)"
if [ -d /run/systemd/system ]; then
  # elenco completo senza filtri: con un filtro senza corrispondenze systemctl esce con 1 (con pipefail fermava il
  # bootstrap); senza filtri un codice diverso da 0 è un errore reale. Il filtro ops-*/enabled lo applica awk.
  if units=$(systemctl list-unit-files --no-legend --no-pager); then
    en=$(awk '$1 ~ /^ops-/ && $2 == "enabled" {print $1}' <<< "$units" | paste -sd' ')
    [ -z "$en" ] && log "  nessuna unit ops-* abilitata" || log "  unit ops-* abilitate: $en"
  else
    log "  ERRORE: systemctl list-unit-files non riuscito (rc=$?): stato delle unit ops-* non verificabile"; v_ok=0
  fi
fi
if cmp -s "$STAGE/ops/docs/bootstrap/ops-installa" "$INSTALLA" && [ "$(stat -c '%U %a' "$INSTALLA")" = "root 755" ] \
   && cmp -s "$STAGE/manifest" "$REF"; then log "  $INSTALLA e impronte di riferimento ($REF) installati"
else log "  $INSTALLA o $REF non conformi"; v_ok=0; fi
[ "$v_ok" = 1 ] || die "verifica finale non superata (vedi sopra)"
[ "$KB_STATE" != scelta ] || log "Knowledge Base: non configurata per scelta (facoltativa; per collegarla: /srv/ops/bin/kb collega)."
if [ "$KB_STATE" = fallita ]; then
  log "ATTENZIONE: Knowledge Base richiesta ma NON collegata: vedere le istruzioni sopra (il resto è completo)."
  log "Il resto è pronto. Prossimo passo, come $ADMIN in un nuovo terminale:  claude"
  exit 4
fi
log "Fatto. Prossimo passo, come $ADMIN in un nuovo terminale:  claude"
log "  (completare il login personale; l'agente rileva i parametri, chiede una sola volta i dati mancanti e poi"
log "   indica il comando unico da lanciare in una sessione SSH: sudo ops-installa)"
