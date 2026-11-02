#!/usr/bin/env bash
# creer_comptes.sh - exigences C1 et C2
# Cree groupes, comptes, repertoires /srv (permissions + ACL) et installe les cles SSH publiques.
# Usage : sudo ./creer_comptes.sh [fichier.csv]
set -euo pipefail
DEPOT="$(dirname "$(readlink -f "$0")")"
CSV="${1:-$DEPOT/comptes.csv}"
CLES_DIR="$DEPOT/config/cles_publiques"
if [[ $EUID -ne 0 ]]; then
echo "Erreur : ce script doit etre lance en root." >&2
exit 1
fi
if [[ ! -f "$CSV" ]]; then
echo "Erreur : fichier $CSV introuvable." >&2
exit 2
fi
creer_groupe() {
local g="$1"
[[ -z "$g" ]] && return 0
if ! getent group "$g" > /dev/null; then
groupadd "$g"
echo "Groupe cree : $g"
fi
}
creer_utilisateur() {
local login="$1" nom="$2" gprinc="$3" gsec="$4"
local shell="/bin/bash"
if [[ "$gprinc" == "invite" ]]; then
shell="/usr/sbin/nologin"
fi
if id "$login" > /dev/null 2>&1; then
usermod -s "$shell" -g "$gprinc" -c "$nom" "$login"
else
useradd -m -s "$shell" -g "$gprinc" -c "$nom" "$login"
echo "Compte cree : $login"
fi
if [[ -n "$gsec" ]]; then
usermod -aG "$gsec" "$login"
fi
chmod 700 "/home/$login"
}
installer_cle() {
local login="$1"
local pub="$CLES_DIR/$login.pub"
[[ -f "$pub" ]] || return 0
local home grp
home="$(getent passwd "$login" | cut -d: -f6)"
grp="$(id -gn "$login")"
install -d -m 700 -o "$login" -g "$grp" "$home/.ssh"
install -m 600 -o "$login" -g "$grp" "$pub" "$home/.ssh/authorized_keys"
echo "Cle installee pour $login"
}
setup_dir() {
local dir="$1"; shift
local entree grp perm
mkdir -p "$dir"
chown root:root "$dir"
setfacl -b "$dir"
chmod 700 "$dir"
for entree in "$@"; do
grp="${entree%%:*}"
perm="${entree##*:}"
setfacl -m "g:${grp}:${perm}" "$dir"
setfacl -d -m "g:${grp}:${perm}" "$dir"
done
}
# --- Passe 1 : les groupes ---
for g in admins support acces_ssh technique chercheurs doctorants invite; do
creer_groupe "$g"
done
while IFS=';' read -r login nom gprinc gsec; do
[[ -z "$login" ]] && continue
creer_groupe "$gprinc"
IFS=',' read -ra liste <<< "$gsec"
for g in "${liste[@]}"; do
creer_groupe "$g"
done
done < <(tail -n +2 "$CSV" | tr -d '\r')
# --- Passe 2 : les comptes et leurs cles ---
while IFS=';' read -r login nom gprinc gsec; do
[[ -z "$login" ]] && continue
creer_utilisateur "$login" "$nom" "$gprinc" "$gsec"
installer_cle "$login"
done < <(tail -n +2 "$CSV" | tr -d '\r')
# --- Repertoires /srv (C2) : droits du tableau du contexte C ---
setup_dir /srv/donnees_brutes technique:rwx chercheurs:r-x doctorants:r-x
setup_dir /srv/analyses chercheurs:rwx doctorants:rwx
setup_dir /srv/publications chercheurs:rwx doctorants:r-x invite:r-x
echo "creer_comptes.sh termine."
