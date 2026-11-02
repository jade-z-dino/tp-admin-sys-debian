#!/usr/bin/env bash
# analyse_logs.sh : rapport des connexions SSH (J4)
# Seuil : variable SEUIL_ECHECS (defaut 5). Periode : PERIODE (defaut "24 hours ago").
# Code de sortie : 0 = ok, 1 = seuil depasse, 2 = erreur d'usage/droits.
set -euo pipefail

SEUIL_ECHECS="${SEUIL_ECHECS:-5}"
PERIODE="${PERIODE:-24 hours ago}"

if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit etre lance en root (sudo)." >&2
  exit 2
fi
if ! [[ "$SEUIL_ECHECS" =~ ^[0-9]+$ ]]; then
  echo "SEUIL_ECHECS doit etre un entier positif." >&2
  exit 2
fi

# Lecture du journal de l'unite ssh (pas de /var/log/auth.log sur Debian 13)
JOURNAL="$(journalctl -u ssh --since "$PERIODE" --no-pager -o cat 2> /dev/null || true)"

# Lignes d'echec : "Invalid user X from IP", "Failed ... for X from IP"
ECHECS="$(echo "$JOURNAL" | grep -E 'Invalid user|Failed (password|publickey)' || true)"

echo "=== Rapport SSH (depuis : $PERIODE) ==="

echo
echo "--- Echecs par adresse IP ---"
echo "$ECHECS" | grep -oE 'from [0-9a-fA-F:.]+' | awk '{print $2}' | sort | uniq -c | sort -rn || true

echo
echo "--- Comptes vises ---"
echo "$ECHECS" | sed -nE 's/.*Invalid user ([^ ]+) from.*/\1/p; s/.*Failed [a-z]+ for (invalid user )?([^ ]+) from.*/\2/p' | sort | uniq -c | sort -rn || true

echo
echo "--- Connexions reussies ---"
echo "$JOURNAL" | grep -E 'Accepted (publickey|password)' | sed -E 's/^(Accepted [a-z]+ for [^ ]+ from [^ ]+).*/\1/' | sort | uniq -c || true

if [[ -z "$ECHECS" ]]; then
  NB=0
else
  NB="$(echo "$ECHECS" | wc -l)"
fi

echo
echo "Total des echecs : $NB (seuil d'alerte : $SEUIL_ECHECS)"
if (( NB > SEUIL_ECHECS )); then
  echo "ALERTE : seuil depasse."
  exit 1
fi
echo "Situation normale."
exit 0
