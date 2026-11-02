#Projet administatrion système avancées et scripting
Auteur : Jade Linot, Aissata Saounera

## Contexte C :La boratoire Biolab. Serveur débian 13 à durcir avec quatre différent 
groupe : Technique, Chercheurs, Doctorants, Invite

Note: Les membre de invite n'ont pas de shell interactif et ne peuvent que récupérer des ficher via SFTP.

Répertoire : srv/donees_brutes, /srv/analyses, /srv/publication
Technique : lecture/écriture
Chercheurs : lecture/écriturre
doctorant : lecure             lecture/écriture
invite : -

#Prérequis

- Vm Debian 13 vierge et installation minimal
- Second disque virtuel pour les sauvegardes
- Accès root sur la VM
- Accès à internet pour installer les dépots débian officiels

## Contenu du dépot 

installer.sh : Reconstruit toute la configuration sur une VM vierge
creer_compte.sh : Crée les compte,groupes, répertoires et ACL à partir de 'compte.csv'
compte.csv : Liste des utilisateurs et de leurs groupes (aucun mdp)
analyse_logs.sh : Rapport des connexion SSH, code de sortie non nul si le seuil d'alerte est dépassé 
sauvegarde.sh : Sauvegarde incrémentale avec versions datées
vérifier.sh : Teste chaque exigence et affiche '[OK]'
config/ : Fichiers de configuration (SHH, sudoers,nftables, fail2ban,journald, clé publique)
Dossier.md : Conformité, chhoix techniques, défense et restauratiion

#installation 

git clone github.com/jade-z-dino/tp-admin-sys-debian
cd tp-admin-sys-debian
sudo ./installer.sh

##Verification

sudo ./verifier.sh

##Sécurité

Aucun mot de passe ni clé privé dabs ce dépot : seules les clés publiques sont versionnées

