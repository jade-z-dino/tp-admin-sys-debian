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
# Paquets
log "Installation des paquets"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq sudo acl rsync openssh-server fail2ban python3-systemd nftables unattended-upgrades
# Comptes, groupes, /srv, ACL, cles (C1, C2)
log "Creation des comptes"
"$DEPOT/creer_comptes.sh"
log "Configuration de sudo"
visudo -cf "$DEPOT/config/sudoers.d/admins"
visudo -cf "$DEPOT/config/sudoers.d/support"
install -m 440 -o root -g root "$DEPOT/config/sudoers.d/admins" /etc/sudoers.d/admins
install -m 440 -o root -g root "$DEPOT/config/sudoers.d/support" /etc/sudoers.d/support
install -m 750 -o root -g root "$DEPOT/analyse_logs.sh" /usr/local/sbin/analyse_logs.sh

for u in $(getent group sudo | cut -d: -f4 | tr ',' ' '); do
  log "retrait de $u du groupe sudo"
  gpasswd -d "$u" sudo
done

log "Configuration de SSH"
install -m 644 -o root -g root "$DEPOT/config/ssh/sshd_config.d/10-durcissement.conf" /etc/ssh/sshd_config.d/10-durcissement.conf
install -m 644 -o root -g root "$DEPOT/config/profile.d/timeout.sh" /etc/profile.d/timeout.sh
sshd -t
systemctl restart ssh

log "Verrouillage du compte root"
passwd -l root

# J1 : fail2ban
apt-get install -y fail2ban python3-systemd nftables
install -m 644 -o root -g root config/fail2ban/jail.d/sshd.conf /etc/fail2ban/jail.d/sshd.conf
systemctl enable fail2ban
systemctl restart fail2ban
