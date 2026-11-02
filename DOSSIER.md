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
