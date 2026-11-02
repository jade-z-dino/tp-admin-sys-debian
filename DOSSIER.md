# Dossier - Projet XTI302-CYB, durcissement d'un serveur Debian 13

**Contexte choisi : C, laboratoire BioLab.** 
**Binôme : Jade Linot et Aissata Saounera.**
**Dépôt : https://github.com/jade-z-dino/tp-admin-sys-debian**


## 1. Tableau de conformité

| ID | Ce qui a été fait | Test verifier.sh | Référence ANSSI |
|----|-------------------|------------------|-----------------|
| C1 | creer_comptes.sh lit comptes.csv ; groupes et comptes créés seulement s'ils n'existent pas (getent, id) : le script est idempotent | test_C1, test_C1_invite | ANSSI-BP-028 (gestion des comptes) |
| C2 | Répertoires de /srv en 700 root, droits par groupe via setfacl, ACL par défaut (-d) pour les fichiers créés plus tard | test_C2 | ANSSI-BP-028 (droits sur les fichiers) |
| C3 | %admins a sudo (/etc/sudoers.d/admins) ; support ne lance que /usr/local/sbin/analyse_logs.sh, sans argument ; groupe sudo vidé | test_C3 | ANSSI-BP-028 (sudo) |
| C4 | passwd -l root ; dossiers personnels en 700 | test_C4 | ANSSI-BP-028 (compte root) |
| S1 | PasswordAuthentication no, KbdInteractiveAuthentication no, PubkeyAuthentication yes | test_S1 | ANSSI Usage sécurisé d'OpenSSH |
| S2 | PermitRootLogin no | test_S2 | ANSSI Usage sécurisé d'OpenSSH |
| S3 | AllowGroups acces_ssh | test_S3 | ANSSI Usage sécurisé d'OpenSSH |
| S4 | MaxAuthTries 4, LoginGraceTime 30, ClientAliveInterval 300 x ClientAliveCountMax 2, TMOUT=900 | test_S4 | ANSSI Usage sécurisé d'OpenSSH |
| S5 | Config dans /etc/ssh/sshd_config.d/10-durcissement.conf ; sshd -t exécuté avant systemctl restart ssh | test_S5 | ANSSI Usage sécurisé d'OpenSSH |
| J1 | fail2ban, jail sshd (3 échecs en 10 min, ban de 10 min), lecture du journal systemd | test_J1 | ANSSI-BP-028 (journalisation et réaction) |
| J2 | nftables : policy drop, SSH et connexions établies autorisés, activé au démarrage ; fail2ban relancé après nftables | test_J2 | ANSSI-BP-028 (pare-feu) |
| J3 | Storage=persistent dans /etc/systemd/journald.conf.d/ | test_J3 | ANSSI-BP-028 (journalisation) |
| J4 | analyse_logs.sh : échecs par IP, comptes visés, connexions réussies ; code de sortie 1 si une IP dépasse le seuil | test_J4 | ANSSI-BP-028 (journalisation) |
| B1 | sauvegarde.sh : rsync -aAXH --link-dest, une version datée par exécution, 7 versions conservées | test_B1 | ANSSI-BP-028 (sauvegarde) |
| B2 | Timer systemd sauvegarde.timer chaque jour à 02:00 ; sorties dans le journal | test_B2 | ANSSI-BP-028 (sauvegarde) |
| B3 | /mnt/sauvegardes en root:admins 750 | test_B3 | ANSSI-BP-028 (droits sur les fichiers) |
| B4 | Restauration testée et procédure rédigée (partie 4) | test_B4 | ANSSI-BP-028 (sauvegarde) |
| D1 | unattended-upgrades installé, 20auto-upgrades actif, timers apt actifs | test_D1 | ANSSI-BP-028 (mises à jour) |
| D2 | Seul SSH écoute ; Apache supprimé ; écoutes restantes expliquées en annexe | test_D2 | ANSSI-BP-028 (services) |
| D3 | Aucun fichier modifiable par tous sauf temporaires ; SUID listés en annexe | test_D3 | ANSSI-BP-028 (droits sur les fichiers) |


## 2. Choix techniques

**Droits sur /srv.** Chaque répertoire est en 700 root, puis on ouvre groupe par groupe avec des ACL. Un groupe qui n'est pas dans le tableau du contexte C n'a donc aucun accès par défaut. Les ACL par défaut font que les fichiers créés plus tard héritent des mêmes droits.

**Mot de passe sudo.** Les admins gardent un mot de passe pour sudo (défini à la main avec passwd, jamais dans Git). Avec NOPASSWD, une clé SSH volée donnerait directement root. support n'a pas de mot de passe, donc NOPASSWD, mais seulement pour un script précis et sans argument. Ce script appartient à root, en 750 dans /usr/local/sbin : s'il était modifiable par support, celui-ci le réécrirait et deviendrait root.

**SSH.**
- "MaxAuthTries 4" : valeur maximale imposée. LoginGraceTime 30 : une connexion qui ne s'authentifie pas en 30 s est coupée.
- "ClientAliveInterval 300 x ClientAliveCountMax 2 coupe un client qui ne répond plus après 10 min. Cela ne coupe pas un utilisateur inactif mais connecté, donc TMOUT=900 (en lecture seule) ferme le shell après 15 min d'inactivité.
- "Match Group invite" avec ForceCommand internal-sftp : les invités ne font que du SFTP, géré par sshd lui-même, donc compatible avec leur shell nologin.
- Un fichier dans "sshd_config.d/" préfixé "10-" : Debian lit ce dossier en premier et la première valeur gagne.

**fail2ban.** 3 échecs en 10 minutes entraînent un ban de 10 minutes. Trois essais tolèrent une faute de frappe mais arrêtent un robot et dix minutes ralentissent beaucoup une attaque sans bloquer longtemps un administrateur qui se trompe par maladresse. Sur Debian 13 minimale, /var/log/auth.log n'existe pas : on lit le journal systemd (backend = systemd) et on filtre sur l'unité ssh.service (journalmatch), parce que les échecs sont écrits par sshd-session. Le mode aggressive détecte aussi les connexions coupées avant authentification.

**nftables.** policy drop sur input, avec seulement le loopback, les connexions établies, SSH (22), le DHCP (réponses UDP 67 vers 68) et ICMP (diagnostic). Le fichier n'utilise pas flush ruleset : cela effacerait la table de fail2ban. On supprime et recrée seulement notre table inet filter. Comme le service nftables vide tout à l'arrêt, installer.sh relance fail2ban juste après.

**Seuil d'alerte de analyse_logs.sh.** 10 échecs depuis une même IP, variable SEUIL_ECHECS modifiable. En dessous, ce sont des fautes de frappe ; au-delà, un comportement de force brute. Le script refuse tout argument et exige root.

**Sauvegarde.** Sauvegarde dans des versions datées plutôt qu'un miroir : si un fichier est supprimé ou chiffré par un rançongiciel, un miroir recopierait la perte, alors qu'une version antérieure permet de revenir en arrière. --link-dest crée des liens physiques pour les fichiers inchangés : chaque version est complète mais ne coûte que ses changements. 7 versions conservées, exécution quotidienne à 02:00 (timer systemd, car cron n'est pas installé en Debian minimale et le journal reçoit les sorties). installer.sh ne formate le second disque que si blkid ne trouve aucun système de fichiers, pour ne jamais effacer les sauvegardes quand on le relance. Le disque est monté par UUID dans `fstab`.

**Mises à jour.** unattended-upgrades avec les sources de sécurité Debian par défaut, uniquement des paquets des dépôts officiels.

**Services.** Apache était présent sur la VM et n'était pas demandé : il a été supprimé (apt purge), et installer.sh le fait aussi si on le retrouve.



## 3. Défense : ce que la configuration rend plus difficile, et ce qu'elle ne couvre pas

**1. Force brute SSH.** Mots de passe refusés, 4 essais par connexion, bannissement par fail2ban après 3 échecs, pare-feu qui n'expose que le port 22. *Ne couvre pas* : une attaque lente ou répartie sur beaucoup d'adresses IP, qui reste sous le seuil de fail2ban.

**2. Vol ou réutilisation de mot de passe.** Aucune connexion SSH par mot de passe : un mot de passe volé ne permet pas d'entrer à distance. *Ne couvre pas* : le vol de la clé privée d'un administrateur (poste compromis, clé sans passphrase), ni un mot de passe sudo volé par quelqu'un déjà connecté.

**3. Utilisateur interne curieux.** Dossiers personnels en 700, `/srv` fermé par défaut, droits par groupe avec ACL : un technicien ne lit pas `/srv/analyses`, un doctorant ne peut pas écrire dans `/srv/donnees_brutes`. *Ne couvre pas* : un administrateur malveillant (il a sudo), ni la fuite de données entre membres d'un même groupe.

**4. Compte invité compromis.** Pas de shell, SFTP uniquement, pas de redirection de ports ni de terminal, lecture seule sur `/srv/publications`. *Ne couvre pas* : la lecture de toutes les publications, ni l'usage de la clé volée tant qu'elle n'est pas retirée.

**5. Rançongiciel ou suppression accidentelle.** Sept versions datées : on revient à un état antérieur (voir partie 4). *Ne couvre pas* : la sauvegarde est sur la même machine, donc un attaquant root ou une panne de la VM l'emporte avec le reste. Elle ne respecte pas la règle 3-2-1 : en production, la copie partirait sur une autre machine, idéalement un autre site.

**6. Compte `support` détourné.** Une seule commande sudo, sans argument, vers un script root:root en 750. *Ne couvre pas* : une faille dans le script lui-même, d'où l'intérêt de le garder court et de ne rien lui passer en argument.


## 4. Restauration d'une sauvegarde

Les sauvegardes sont dans /mnt/sauvegardes, une version datee par execution (AAAA-MM-JJ_HH-MM-SS).
Le lien latest pointe vers la plus recente. On garde 7 versions.

1. Lister les versions : ls /mnt/sauvegardes
2. Choisir la version d'avant l'incident (ou latest).
3. Restaurer un fichier, avec ses droits et ses ACL :
   rsync -aAX /mnt/sauvegardes/VERSION/srv/analyses/fichier.txt /srv/analyses/
4. Verifier : cat /srv/analyses/fichier.txt et getfacl /srv/analyses/fichier.txt

Test realise : creation de /srv/analyses/essai.txt, sauvegarde, suppression, restauration depuis latest, contenu identique.

## Annexe : fichiers SUID

Un fichier SUID s'exécute avec les droits de son propriétaire (root), quel que soit l'utilisateur qui le lance. Chacun de ceux-ci est livré avec Debian et nécessaire au fonctionnement normal. Le risque est qu'un bug dans l'un d'eux donne les droits root, d'où l'intérêt de garder le système à jour (D1).

- `mount` et `umount` : montent et démontent des systèmes de fichiers.
- `passwd` : permet à un utilisateur de changer son mot de passe (écrit dans /etc/shadow, réservé à root).
- `chfn` : modifie les informations personnelles d'un compte dans /etc/passwd.
- `chsh` : change le shell de connexion de l'utilisateur.
- `gpasswd` : administre les groupes et leurs membres (/etc/group).
- `newgrp` : change de groupe principal pour la session en cours.
- `su` : change d'utilisateur.
- `sudo` : exécute une commande avec les droits d'un autre utilisateur (voir exigence C3).
- `ssh-keysign` : aide d'OpenSSH pour l'authentification par hôte, qui lit les clés privées de la machine (réservées à root). Cette authentification n'est pas activée ici.
- `dbus-daemon-launch-helper` : lance les services du bus système D-Bus avec les privilèges adaptés.

## Annexe : écoutes réseau (ss -tulpn)

- tcp 22 : SSH, le seul service volontairement exposé (D2).
- udp 68 : client DHCP IPv4, nécessaire pour obtenir l'adresse IP de la VM.
- udp 546 : client DHCPv6, il n'attend que des réponses. Le pare-feu refuse tout trafic entrant non sollicité (voir J2).
- Le serveur web Apache, présent à l'origine sur la VM, a été supprimé : il n'était pas demandé et exposait le port 80.
