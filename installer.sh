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

# J2 : pare-feu nftables
install -m 644 -o root -g root config/nftables.conf /etc/nftables.conf
nft -c -f /etc/nftables.conf
systemctl enable nftables
systemctl restart nftables
systemctl restart fail2ban

# J3 : journal persistant
mkdir -p /etc/systemd/journald.conf.d /var/log/journal
install -m 644 -o root -g root config/journald.conf /etc/systemd/journald.conf.d/10-persistant.conf
systemctl restart systemd-journald

# D1 : mises a jour de securite automatiques
apt-get install -y unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
systemctl enable apt-daily-upgrade.timer
systemctl start apt-daily-upgrade.timer

# J4 : analyse_logs.sh
install -m 750 -o root -g root analyse_logs.sh /usr/local/sbin/analyse_logs.sh

# --- B1/B3 : disque de sauvegarde ---
DISQUE_SAUV="/dev/sdb"
mkdir -p /mnt/sauvegardes
if ! blkid "$DISQUE_SAUV" > /dev/null 2>&1; then
  mkfs.ext4 -L sauvegardes "$DISQUE_SAUV"
fi
UUID_SAUV="$(blkid -s UUID -o value "$DISQUE_SAUV")"
if ! grep -q "$UUID_SAUV" /etc/fstab; then
  echo "UUID=$UUID_SAUV /mnt/sauvegardes ext4 defaults,nofail 0 2" >> /etc/fstab
  systemctl daemon-reload
fi
mountpoint -q /mnt/sauvegardes || mount /mnt/sauvegardes
chown root:admins /mnt/sauvegardes
chmod 750 /mnt/sauvegardes

# B1 : sauvegarde.sh
apt-get install -y rsync
install -m 750 -o root -g root sauvegarde.sh /usr/local/sbin/sauvegarde.sh

# B2 : planification de la sauvegarde
install -m 644 -o root -g root "$DEPOT/config/systemd/sauvegarde.service" /etc/systemd/system/sauvegarde.service
install -m 644 -o root -g root "$DEPOT/config/systemd/sauvegarde.timer" /etc/systemd/system/sauvegarde.timer
systemctl daemon-reload
systemctl enable --now sauvegarde.timer
