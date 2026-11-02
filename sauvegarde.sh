#!/usr/bin/env bash
# sauvegarde.sh : sauvegarde incrementale de /srv et /etc (B1)
# Chaque execution cree une version datee dans /mnt/sauvegardes.
# Les fichiers inchanges sont des liens physiques vers la version precedente.
set -euo pipefail

DEST="/mnt/sauvegardes"
SOURCES=(/srv /etc)
CONSERVER="${CONSERVER:-7}"
DATE="$(date +%Y-%m-%d_%H-%M-%S)"

if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit etre lance en root." >&2
  exit 2
fi
if ! mountpoint -q "$DEST"; then
  echo "ERREUR : $DEST n'est pas monte (disque de sauvegarde absent)." >&2
  exit 3
fi

PRECEDENTE=""
if [[ -L "$DEST/latest" ]]; then
  PRECEDENTE="$(readlink -f "$DEST/latest")"
fi

# Version en cours : suffixe .partiel tant que rsync n'a pas fini
mkdir -p "$DEST/$DATE.partiel"
OPTIONS=(-aAXH --delete --numeric-ids --relative)
if [[ -n "$PRECEDENTE" ]]; then
  OPTIONS+=(--link-dest="$PRECEDENTE")
fi

echo "Sauvegarde $DATE : debut"
rsync "${OPTIONS[@]}" "${SOURCES[@]}" "$DEST/$DATE.partiel/"
mv "$DEST/$DATE.partiel" "$DEST/$DATE"
ln -sfn "$DEST/$DATE" "$DEST/latest"
echo "Sauvegarde $DATE : terminee"

# Rotation : garder les N dernieres versions
mapfile -t VERSIONS < <(find "$DEST" -mindepth 1 -maxdepth 1 -type d -name '20*' ! -name '*.partiel' | sort)
NB=${#VERSIONS[@]}
if (( NB > CONSERVER )); then
  for ancienne in "${VERSIONS[@]:0:NB-CONSERVER}"; do
    echo "Suppression de l'ancienne version : $ancienne"
    rm -rf "$ancienne"
  done
fi
exit 0
