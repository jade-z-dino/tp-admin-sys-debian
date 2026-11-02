#!/usr/bin/env bash
# verifier.sh : teste chaque exigence, ne modifie jamais le systeme
# Pas de set -e ni pipefail : un test rate ne doit pas arreter le script.
set -u
export LC_ALL=C
export PATH="$PATH:/usr/sbin:/sbin"

DEPOT="$(dirname "$(readlink -f "$0")")"
CSV="$DEPOT/comptes.csv"
TOTAL=0
REUSSIS=0
ERREURS=0

if [[ $EUID -ne 0 ]]; then
  echo "Ce script doit etre lance en root (sudo ./verifier.sh)." >&2
  exit 2
fi

ok() { echo "[OK] $1 $2"; TOTAL=$((TOTAL + 1)); REUSSIS=$((REUSSIS + 1)); }
ko() { echo "[KO] $1 $2"; TOTAL=$((TOTAL + 1)); }
erreur() { echo "     -> $*"; ERREURS=$((ERREURS + 1)); }
bilan() {
  if (( ERREURS == 0 )); then ok "$1" "$2"; else ko "$1" "$3"; fi
  ERREURS=0
}

un_membre() { # un login dont le groupe PRINCIPAL est $1
  local gid
  gid="$(getent group "$1" | cut -d: -f3)"
  getent passwd | awk -F: -v gid="$gid" '$4 == gid {print $1; exit}'
}
peut_lister() { sudo -u "$1" ls "$2" > /dev/null 2>&1; }
peut_ecrire() {
  local f="$2/.vtest_$$"
  if sudo -u "$1" touch "$f" 2> /dev/null; then rm -f "$f"; return 0; fi
  return 1
}
verif() { # verif UTILISATEUR FONCTION CHEMIN oui non
  local res="non"
  if "$2" "$1" "$3"; then res="oui"; fi
  if [[ "$res" != "$4" ]]; then
  erreur "$1 : $2 $3 = $res (attendu : $4)"
  fi
}
sshd_val() { # interroge la configuration effective du serveur SSH pour en extraire et afficher la valeur exacte dun paramètre spécifique que l'on lui passe en argument
 sshd -T 2> /dev/null | grep -i "^$1 " | awk '{print $2}'; }

# TESTS

test_C1() {
  local login nom gp gs g liste
  while IFS=';' read -r login nom gp gs; do
    [[ -z "$login" ]] && continue
    if ! id "$login" > /dev/null 2>&1; then
      erreur "compte $login absent"
      continue
    fi
    [[ "$(id -gn "$login")" == "$gp" ]] || erreur "$login : groupe principal incorrect (attendu $gp)"
    IFS=',' read -ra liste <<< "$gs"
    for g in "${liste[@]}"; do
      [[ -z "$g" ]] && continue
      id -nG "$login" | grep -qw "$g" || erreur "$login n'est pas dans le groupe $g"
    done
  done < <(tail -n +2 "$CSV" | tr -d '\r')
  bilan C1 "comptes et groupes conformes a comptes.csv" "comptes ou groupes non conformes a comptes.csv"
}


test_C1_invite() {
  local login nom gp gs shell
  while IFS=';' read -r login nom gp gs; do
    [[ "$gp" == "invite" ]] || continue
    shell="$(getent passwd "$login" | cut -d: -f7)"
    [[ "$shell" == */nologin ]] || erreur "$login a un shell ($shell)"
  done < <(tail -n +2 "$CSV" | tr -d '\r')
  sshd -T -C "user=$(un_membre invite),host=localhost,addr=127.0.0.1" 2>/dev/null | grep -qi '^forcecommand internal-sftp' || erreur "invite n'est pas limite au SFTP"
    bilan C1 "invite : nologin et SFTP uniquement" "invite : shell ou SFTP mal configure"
}

test_C2() {
  local t c d i f
  t="$(un_membre technique)"; c="$(un_membre chercheurs)"
  d="$(un_membre doctorants)"; i="$(un_membre invite)" 
  verif "$t" peut_ecrire /srv/donnees_brutes oui
  verif "$c" peut_lister /srv/donnees_brutes oui
  verif "$c" peut_ecrire /srv/donnees_brutes non
  verif "$d" peut_lister /srv/donnees_brutes oui
  verif "$d" peut_ecrire /srv/donnees_brutes non
  verif "$i" peut_lister /srv/donnees_brutes non
  bilan C2 "droits de /srv/donnees_brutes conformes" "droits incorrects sur /srv/donnees_brutes"
  verif "$t" peut_lister /srv/analyses non
  verif "$c" peut_ecrire /srv/analyses oui
  verif "$d" peut_ecrire /srv/analyses oui
  verif "$i" peut_lister /srv/analyses non
  bilan C2 "droits de /srv/analyses conformes" "droits incorrects sur /srv/analyses"
  verif "$t" peut_lister /srv/publications non
  verif "$c" peut_ecrire /srv/publications oui
  verif "$d" peut_lister /srv/publications oui
  verif "$d" peut_ecrire /srv/publications non
  verif "$i" peut_lister /srv/publications oui
  verif "$i" peut_ecrire /srv/publications non
  bilan C2 "droits de /srv/publications conformes" "droits incorrects sur /srv/publications"
# ACL par defaut : un fichier cree PLUS TARD doit lui aussi respecter les droits
  f="/srv/analyses/.vtest_acl_$$"
  sudo -u "$c" touch "$f" 2> /dev/null
  sudo -u "$d" test -w "$f" || erreur "un doctorant ne peut pas ecrire dans un fichier cree par un chercheur"
  if sudo -u "$t" test -r "$f"; then erreur "technique peut lire/srv/analyses"; fi
rm -f "$f"
bilan C2 "ACL par defaut appliquees aux nouveaux fichiers" "ACL par defaut absentes ou incorrectes" 
}

test_C3() {
  local login nom gp gs sortie
  [[ -f /etc/sudoers.d/admins ]] || erreur "/etc/sudoers.d/admins absent"
  while IFS=';' read -r login nom gp gs; do
    [[ -z "$login" ]] && continue
    case "$gp" in
      admins) sudo -l -U "$login" < /dev/null 2>&1 | grep -q "(ALL" || erreur "$login (admin) n'a pas sudo" ;;
      support) ;;
      *) sudo -l -U "$login" < /dev/null 2>&1 | grep -q "not allowed" || erreur "$login a des droits sudo" ;;
    esac
  done < <(tail -n +2 "$CSV" | tr -d '\r')
  bilan C3 "admins ont sudo, aucun autre compte (hors support) n'en a" "droits sudo incorrects"
  sortie="$(sudo -l -U support 2>&1)"
  echo "$sortie" | grep -q "analyse_logs.sh" || erreur "support ne peut pas lancer analyse_logs.sh"
  if echo "$sortie" | grep -Eq "\) (NOPASSWD: )?ALL"; then erreur "support a un sudo trop large"; fi
  bilan C3 "support ne peut lancer que analyse_logs.sh" "sudo de support incorrect"
}


test_C4() {
  local etat login nom gp gs perm
  etat="$(passwd -S root | awk '{print $2}')"
  [[ "$etat" == "L" ]] || erreur "root n'est pas verrouille (etat : $etat)"
  bilan C4 "compte root verrouille" "compte root non verrouille"
  while IFS=';' read -r login nom gp gs; do
    [[ -z "$login" ]] && continue
    perm="$(stat -c %a "/home/$login" 2> /dev/null || echo 777)"
    [[ "${perm: -1}" == "0" ]] || erreur "/home/$login est en $perm"
  done < <(tail -n +2 "$CSV" | tr -d '\r')
  bilan C4 "dossiers personnels fermes aux autres" "dossiers personnels trop ouverts"
}

test_S1() {
  [[ "$(sshd_val passwordauthentication)" == "no" ]] || erreur "PasswordAuthentication n'est pas a no"
  [[ "$(sshd_val kbdinteractiveauthentication)" == "no" ]] || erreur "KbdInteractiveAuthentication n'est pas a no"
  [[ "$(sshd_val pubkeyauthentication)" == "yes" ]] || erreur "PubkeyAuthentication n'est pas a yes"
  bilan S1 "connexion par cle uniquement, mot de passe refuse" "authentification SSH mal configuree"
}

test_S2() {
  [[ "$(sshd_val permitrootlogin)" == "no" ]] || erreur "PermitRootLogin n'est pas a no"
  bilan S2 "connexion root refusee" "connexion root possible"
}

test_S3() {
  [[ "$(sshd_val allowgroups)" == "acces_ssh" ]] || erreur "AllowGroups n'est pas acces_ssh"
  bilan S3 "seul le groupe acces_ssh peut se connecter" "AllowGroups incorrect"
}

test_S4() {
  local essais interval count
  essais="$(sshd_val maxauthtries)"
  interval="$(sshd_val clientaliveinterval)"
  count="$(sshd_val clientalivecountmax)"
  (( essais >= 1 && essais <= 4 )) || erreur "MaxAuthTries = $essais (attendu: 1 a 4)"
  bilan S4 "au plus 4 essais d'authentification" "MaxAuthTries incorrect"
  (( interval * count > 0 && interval * count <= 900 )) || erreur "ClientAlive = $((interval * count)) s (attendu : 1 a 900)"
  grep -qs 'TMOUT=900' /etc/profile.d/*.sh || erreur "TMOUT=900 absent de /etc/profile.d"
  bilan S4 "session inactive fermee en 15 min au plus" "delai d'inactivite incorrect"
}

test_S5() {
  [[ -f /etc/ssh/sshd_config.d/10-durcissement.conf ]] || erreur "fichier 10- durcissement.conf absent de /etc/ssh/sshd_config.d"
  sshd -t 2> /dev/null || erreur "sshd -t signale une erreur"
  bilan S5 "configuration dans sshd_config.d et valide (sshd -t)" "configuration SSH absente ou invalide"
}

# NOUVEAUX TESTS 

test_B2() {
  systemctl is-enabled --quiet sauvegarde.timer || erreur "sauvegarde.timer non active"
  systemctl is-active --quiet sauvegarde.timer || erreur "sauvegarde.timer non demarre"
  bilan B2 "sauvegarde planifiee (timer systemd, journalisee)" "sauvegarde non planifiee"
}

test_B1() {
  local nb
  nb="$(find /mnt/sauvegardes -mindepth 1 -maxdepth 1 -type d -name '20*' 2> /dev/null | wc -l)"
  mountpoint -q /mnt/sauvegardes || erreur "le disque de sauvegarde n'est pas monte"
  [[ -x /usr/local/sbin/sauvegarde.sh ]] || erreur "sauvegarde.sh absent"
  (( nb >= 1 )) || erreur "aucune version de sauvegarde (lance sauvegarde.sh)"
  grep -q -- '--link-dest' /usr/local/sbin/sauvegarde.sh 2> /dev/null || erreur "sauvegarde non incrementale (pas de --link-dest)"
  diff <(getfacl -p /srv/analyses 2> /dev/null | grep -v '^# file') <(getfacl -p /mnt/sauvegardes/latest/srv/analyses 2> /dev/null | grep -v '^# file') > /dev/null || erreur "ACL de /srv/analyses non conservees dans la derniere version"
  bilan B1 "sauvegarde incrementale datee avec ACL ($nb version(s))" "sauvegarde absente ou incomplete"
}

test_B3() {
  [[ "$(stat -c '%U:%G:%a' /mnt/sauvegardes 2> /dev/null)" == "root:admins:750" ]] || erreur "/mnt/sauvegardes devrait etre root:admins en 750"
  bilan B3 "sauvegardes reservees aux administrateurs" "droits incorrects sur /mnt/sauvegardes"
}

test_J4() {
  local script="/usr/local/sbin/analyse_logs.sh" code
  [[ -x "$script" ]] || erreur "$script absent ou non executable"
  [[ "$(stat -c '%U:%a' "$script" 2> /dev/null)" == "root:750" ]] || erreur "$script devrait etre root:750"
  SEUIL_ECHECS=0 "$script" > /dev/null 2>&1; code=$?
  [[ $code -eq 1 ]] || erreur "seuil 0 : code $code (attendu 1)"
  SEUIL_ECHECS=999999 "$script" > /dev/null 2>&1; code=$?
  [[ $code -eq 0 ]] || erreur "seuil enorme : code $code (attendu 0)"
  bilan J4 "analyse_logs.sh : rapport et code de sortie selon le seuil" "analyse_logs.sh incorrect"
}

test_D1() {
  dpkg -s unattended-upgrades > /dev/null 2>&1 || erreur "paquet unattended-upgrades absent"
  grep -qs 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades || erreur "20auto-upgrades ne l'active pas"
  systemctl is-enabled --quiet apt-daily-upgrade.timer || erreur "timer apt-daily-upgrade inactif"
  bilan D1 "mises a jour de securite automatiques" "mises a jour automatiques non configurees"
}

test_J3() {
  grep -rqs '^Storage=persistent' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/ || erreur "Storage=persistent absent"
  [[ -d /var/log/journal ]] || erreur "/var/log/journal n'existe pas"
  bilan J3 "journal systeme persistant" "journal non persistant"
}

test_J2() {
  nft list chain inet filter input 2> /dev/null | grep -q 'policy drop' || erreur "politique par defaut de input : pas drop"
  nft list chain inet filter input 2> /dev/null | grep -q 'dport 22' || erreur "SSH (port 22) non autorise"
  bilan J2 "pare-feu : tout refuse par defaut, seul SSH est autorise" "pare-feu mal configure"
  systemctl is-enabled --quiet nftables || erreur "nftables n'est pas active au demarrage"
  fail2ban-client get sshd actions 2> /dev/null | grep -qi 'nftables' || erreur "fail2ban n'utilise pas l'action nftables"
  bilan J2 "nftables persistant, fail2ban branche sur nftables" "nftables non persistant ou fail2ban mal branche"
}

test_J1() {
  systemctl is-active --quiet fail2ban || erreur "fail2ban n'est pas actif"
  fail2ban-client status sshd > /dev/null 2>&1 || erreur "la jail sshd n'est pas active"
  bilan J1 "fail2ban actif avec la jail sshd" "fail2ban ou jail sshd absents"
}
# Lancement : toute fonction dont le nom commence par test

test_B4() {
  grep -qi 'restauration' "$DEPOT/DOSSIER.md" 2> /dev/null || erreur "procedure de restauration absente de DOSSIER.md"
  cmp -s /etc/hostname /mnt/sauvegardes/latest/etc/hostname || erreur "un fichier de la sauvegarde differe de l'original"
  bilan B4 "restauration documentee, fichier de la sauvegarde identique" "restauration non documentee ou fichier different"
}
for fonction in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
  "$fonction"
done

echo "--- $REUSSIS / $TOTAL tests reussis"
if (( REUSSIS == TOTAL )); then exit 0; else exit 1; fi
