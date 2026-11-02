# Dossier - Projet XTI302-CYB (contexte C, BioLab)

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
