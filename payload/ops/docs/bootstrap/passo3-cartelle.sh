#!/bin/bash
# Passo 3 — struttura delle cartelle dei dati e del backup locale in <DATA_MOUNT> (DATA_MOUNT da host.conf).
#
# Uso (terminale vero, non la modalità ! di Claude Code):
#   sudo bash /srv/ops/docs/bootstrap/passo3-cartelle.sh            # PRECHECK + MODIFICA + VERIFY
#   sudo bash /srv/ops/docs/bootstrap/passo3-cartelle.sh --dry-run  # solo PRECHECK, nessuna scrittura
#   sudo bash /srv/ops/docs/bootstrap/passo3-cartelle.sh --rollback # rimuove le cartelle create da questo script
#
# Crea solo, se mancano: <DATA_MOUNT>/dati (root 0755), <DATA_MOUNT>/dati/backup e .../backup/database (root 0750).
# Se <DATA_MOUNT> compare in /etc/fstab deve essere montato (altrimenti le cartelle finirebbero sul filesystem
# sottostante); se non è un punto di montaggio vale il layout a disco unico della sezione 0.
# Una cartella già presente con proprietario e permessi attesi resta invariata; se differiscono lo script si
# ferma nel PRECHECK senza modificare nulla (nessuna correzione automatica).
# Ogni cartella creata viene aggiunta (mai sovrascritta) al manifest MANIFEST, root 0600 in una cartella root
# 0700: il rollback rimuove con rmdir solo quelle, e conserva quelle non vuote.
# Non tocca partizioni, volumi, fstab, /srv/ops né la Knowledge Base; nessun chmod/chown, nulla di ricorsivo.
# /srv/docker e borg-repo-plain/ nascono nei passi 8 e 10. Ripetibile.
set -euo pipefail

OWNER=root:root
MANIFEST_DIR=/var/lib/ops-bootstrap
MANIFEST=$MANIFEST_DIR/passo3-cartelle.manifest
# shellcheck source=passi-comune.sh
. "$(dirname "$0")/passi-comune.sh"
# Controllo limitato: proprietario, permessi e inode di queste sole directory (non il loro contenuto); la copia della
# Knowledge Base solo se è stata recuperata.
PROTECTED=("$OPS" "$OPS/.git")
[ -d "$OPS/knowledge-base/.git" ] && PROTECTED+=("$OPS/knowledge-base" "$OPS/knowledge-base/.git")

MODE=apply
case "${1:-}" in
  "") ;;
  --dry-run) MODE=dry ;;
  --rollback) MODE=rollback ;;
  *) echo "argomento sconosciuto: $1" >&2; exit 2 ;;
esac

die() { echo "ERRORE: $*" >&2; exit 1; }
attrs() { stat -c '%U:%G %a' -- "$1"; }
snapshot() { stat -c '%n %U:%G %a inode=%i' -- "${PROTECTED[@]}"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

[ "$(id -u)" -eq 0 ] || die "va eseguito con sudo"
load_host_conf
need DATA_MOUNT "punto di montaggio del disco dati (sezione 0)"
DIRS=("$DATA_MOUNT/dati:0755" "$DATA_MOUNT/dati/backup:0750" "$DATA_MOUNT/dati/backup/database:0750")

# Il manifest, se esiste, deve essere protetto e non un collegamento.
check_manifest() {
  if [ -e "$MANIFEST_DIR" ] || [ -L "$MANIFEST_DIR" ]; then
    [ -d "$MANIFEST_DIR" ] && [ ! -L "$MANIFEST_DIR" ] || die "$MANIFEST_DIR non è una cartella reale"
    [ "$(attrs "$MANIFEST_DIR")" = "$OWNER 700" ] || die "$MANIFEST_DIR: $(attrs "$MANIFEST_DIR") (atteso $OWNER 700)"
  fi
  if [ -e "$MANIFEST" ] || [ -L "$MANIFEST" ]; then
    [ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || die "$MANIFEST non è un file regolare"
    [ "$(attrs "$MANIFEST")" = "$OWNER 600" ] || die "$MANIFEST: $(attrs "$MANIFEST") (atteso $OWNER 600)"
  fi
}

# ---- ROLLBACK: solo le cartelle che il manifest dà come create e non ancora rimosse, in ordine inverso.
if [ "$MODE" = rollback ]; then
  echo "== ROLLBACK"
  check_manifest
  [ -f "$MANIFEST" ] || { echo "nessun manifest: questo script non ha creato cartelle, nulla da fare"; exit 0; }
  # righe: "<data> created <inode> <percorso>" / "<data> removed <inode> <percorso>"; vale l'ultima per percorso
  mapfile -t TODO < <(awk '{ p=$4; for (i=5;i<=NF;i++) p=p" "$i; act[p]=$2; ino[p]=$3; if (!(p in seen)) { seen[p]=1; ord[++n]=p } }
                          END { for (i=n;i>=1;i--) if (act[ord[i]]=="created") print ino[ord[i]] " " ord[i] }' "$MANIFEST")
  [ "${#TODO[@]}" -gt 0 ] || { echo "nessuna cartella da rimuovere"; exit 0; }
  rc=0
  for row in "${TODO[@]}"; do
    ino=${row%% *} path=${row#* }
    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
      echo "già assente: $path"; echo "$(now) removed $ino $path" >> "$MANIFEST"; continue
    fi
    if [ -L "$path" ] || [ ! -d "$path" ] || [ "$(stat -c %i -- "$path")" != "$ino" ]; then
      echo "ERRORE: $path non è più la cartella creata dallo script (tipo o inode diverso): lasciata"; rc=1; continue
    fi
    if [ -n "$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
      echo "conservata (non vuota): $path"; continue
    fi
    if err=$(rmdir -- "$path" 2>&1); then
      echo "rimossa: $path"; echo "$(now) removed $ino $path" >> "$MANIFEST"
    else
      echo "ERRORE: rmdir $path: $err"; rc=1
    fi
  done
  exit $rc
fi

# ---- PRECHECK (nessuna scrittura)
echo "== PRECHECK"
[ -d "$DATA_MOUNT" ] && [ ! -L "$DATA_MOUNT" ] || die "$DATA_MOUNT non è una cartella reale"
if findmnt -n --mountpoint "$DATA_MOUNT" >/dev/null; then
  echo "ok  $DATA_MOUNT montato ($(findmnt -n -o SOURCE,FSTYPE --mountpoint "$DATA_MOUNT"))"
elif awk -v m="$DATA_MOUNT" '$1 !~ /^#/ && $2 == m' /etc/fstab | grep -q .; then
  die "$DATA_MOUNT è in /etc/fstab ma non è montato: le cartelle finirebbero sul filesystem sottostante, fermarsi"
else
  echo "nota: $DATA_MOUNT non è un punto di montaggio: disco unico, cartelle su $(findmnt -n -o TARGET --target "$DATA_MOUNT") (sezione 0)"
fi
for p in "${PROTECTED[@]}"; do [ -d "$p" ] || die "manca $p"; done
check_manifest
CREATE=()
bad=0
for d in "${DIRS[@]}"; do
  path=${d%%:*} want="$OWNER ${d##*:}"; want=${want/ 0/ }
  if [ -L "$path" ]; then echo "KO  $path è un collegamento simbolico"; bad=1; continue; fi
  if [ ! -e "$path" ]; then echo "da creare: $path ($want)"; CREATE+=("$d"); continue; fi
  if [ ! -d "$path" ]; then echo "KO  $path esiste e non è una cartella"; bad=1; continue; fi
  got=$(attrs "$path")
  if [ "$got" = "$want" ]; then echo "ok  presente, lasciata invariata: $path ($got)"
  else echo "KO  presente con $got, atteso $want: $path"; bad=1; fi
done
[ "$bad" -eq 0 ] || die "cartelle preesistenti non conformi: nessuna modifica eseguita, da valutare a mano"
BEFORE=$(snapshot)
df -hT "$DATA_MOUNT" | tail -1
[ "$MODE" = dry ] && { echo "== DRY-RUN: nessuna scrittura"; exit 0; }

# ---- MODIFICA (solo creazione delle cartelle mancanti, una alla volta)
echo "== MODIFICA"
if [ "${#CREATE[@]}" -eq 0 ]; then
  echo "nulla da creare"
else
  # manifest pronto e scrivibile prima di creare qualunque cartella; mai troncato
  install -d -o root -g root -m 0700 -- "$MANIFEST_DIR"
  ( umask 077; : >> "$MANIFEST" )
  chown root:root -- "$MANIFEST"; chmod 0600 -- "$MANIFEST"   # solo il manifest, appena creato o già conforme
  check_manifest
  for d in "${CREATE[@]}"; do
    path=${d%%:*} mode=${d##*:}
    install -d -o root -g root -m "$mode" -- "$path"   # i genitori esistono già: l'elenco va dall'alto in basso
    echo "$(now) created $(stat -c %i -- "$path") $path" >> "$MANIFEST"
    echo "creata: $path"
  done
fi

# ---- VERIFY
echo "== VERIFY"
rc=0
for d in "${DIRS[@]}"; do
  path=${d%%:*} want="$OWNER ${d##*:}"; want=${want/ 0/ }
  got=$(attrs "$path")
  if [ "$got" = "$want" ]; then echo "ok  $path $got"; else echo "KO  $path $got (atteso $want)"; rc=1; fi
done
if [ "$(snapshot)" = "$BEFORE" ]; then
  echo "ok  proprietario, permessi e inode invariati per: ${PROTECTED[*]} (contenuto non verificato)"
else
  echo "KO  proprietario, permessi o inode cambiati in: ${PROTECTED[*]}"; rc=1
fi
[ -f "$MANIFEST" ] && { echo "manifest $MANIFEST ($(attrs "$MANIFEST")):"; cat -- "$MANIFEST"; }
exit $rc
