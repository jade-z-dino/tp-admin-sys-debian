#!/usr/bin/env bash
# installer.sh - reconstruit toute la configuration sur une Debian 13 vierge
# Idempotent : on peut le relancer sans danger.
set -euo pipefail
DEPOT="$(dirname "$(readlink -f "$0")")"
log() { echo "[installer] $*"; }
if [[ $EUID -ne 0 ]]; then
echo "Erreur : ce script doit etre lance en root (sudo ./installer.sh)."
>&2
exit 1
fi
# --- Paquets ---
log "Installation des paquets"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq sudo acl rsync openssh-server fail2ban python3-systemd nftables unattended-upgrades
# --- Comptes, groupes, /srv, ACL, cles (C1, C2) ---
log "Creation des comptes"
"$DEPOT/creer_comptes.sh"
