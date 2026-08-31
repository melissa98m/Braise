#!/usr/bin/env bash
# Provisionnement d'un VPS Ubuntu 22.04/24.04 tout neuf (cahier des charges D.7 : Hetzner/OVH/
# Scaleway) — installe Docker, ouvre uniquement les ports nécessaires, et prépare un utilisateur
# de déploiement non-root. Idempotent (vérifie avant d'agir), pensé pour être relancé sans dégât
# si une étape a échoué en cours de route.
#
# Non vérifié contre un vrai VPS depuis cet environnement (pas de VPS disponible ici) — relu avec
# soin, mais teste-le sur une machine jetable avant de t'y fier en prod. Voir docs/DEPLOYMENT.md
# pour la suite (déploiement de l'app elle-même, qui n'est pas le rôle de ce script).
#
# Usage (en root, ou via sudo, sur le VPS tout neuf) :
#   curl -fsSL https://raw.githubusercontent.com/<ton-repo>/main/infra/deploy/provision.sh | bash
#   # ou, après avoir cloné le repo sur le VPS :
#   sudo bash infra/deploy/provision.sh
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-braise}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Ce script doit tourner en root (ou via sudo)." >&2
  exit 1
fi

echo "==> Mise à jour du système..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

echo "==> Mises à jour de sécurité automatiques (unattended-upgrades)..."
apt-get install -y -qq unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> Pare-feu (ufw) : uniquement SSH, HTTP, HTTPS..."
apt-get install -y -qq ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> Docker Engine + plugin Compose (script officiel Docker)..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
else
  echo "Docker déjà installé, on passe."
fi

echo "==> Utilisateur de déploiement non-root ($DEPLOY_USER)..."
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
  usermod -aG docker "$DEPLOY_USER"
  echo "Créé. Copie ta clé SSH publique dans /home/$DEPLOY_USER/.ssh/authorized_keys avant de"
  echo "couper l'accès root par mot de passe (voir docs/DEPLOYMENT.md)."
else
  usermod -aG docker "$DEPLOY_USER" || true
  echo "Existe déjà, ajouté au groupe docker si besoin."
fi

echo "==> Fait. Prochaines étapes (docs/DEPLOYMENT.md) :"
echo "  1. Vérifier l'accès SSH par clé pour '$DEPLOY_USER' AVANT de fermer cette session root."
echo "  2. Pointer les domaines (API_DOMAIN/OBJECTS_DOMAIN/APP_DOMAIN) vers l'IP de ce serveur."
echo "  3. En tant que '$DEPLOY_USER' : cloner le dépôt, copier .env.prod.example en .env,"
echo "     générer les vrais secrets, puis :"
echo "       docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d"
