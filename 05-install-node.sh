#!/usr/bin/env bash
# Установка ноды Remnawave (Xray) на сервере.
# Данные берутся из панели: Nodes -> Management -> "+" -> Copy docker-compose.yml
# Использование: bash 05-install-node.sh <NODE_PORT> <SECRET_KEY> [IP_ПАНЕЛИ]
set -euo pipefail

NODE_PORT="${1:?Укажите NODE_PORT (например 2222)}"
SECRET_KEY="${2:?Укажите SECRET_KEY из карточки ноды}"
PANEL_IP="${3:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите от root" >&2
  exit 1
fi

echo "==> Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

mkdir -p /opt/remnanode && cd /opt/remnanode

cat > docker-compose.yml <<EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    restart: always
    network_mode: host
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
EOF

echo "==> Firewall: порт ноды"
if [ -n "$PANEL_IP" ]; then
  ufw allow from "$PANEL_IP" to any port "$NODE_PORT" proto tcp comment 'remnawave panel'
else
  echo "IP панели не указан — откройте порт ${NODE_PORT} вручную только для IP панели:" >&2
  echo "  ufw allow from <IP_ПАНЕЛИ> to any port ${NODE_PORT} proto tcp" >&2
fi
ufw allow 443/tcp

echo "==> Запуск"
docker compose up -d
sleep 5
docker compose logs --tail=30

echo
echo "Готово. Вернитесь в панель -> Next -> выберите Config Profile -> Create."
