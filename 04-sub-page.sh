#!/usr/bin/env bash
# Subscription Page (красивая страница подписки на том же сервере, что и панель).
# Использование: bash 04-sub-page.sh '<API_TOKEN_ИЗ_ПАНЕЛИ>'
# Токен: панель -> Settings -> API Tokens -> Create.
set -euo pipefail

TOKEN="${1:?Укажите API-токен из панели (Settings -> API Tokens)}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите от root" >&2
  exit 1
fi

docker network create remnawave-network >/dev/null 2>&1 || true

mkdir -p /opt/remnawave/subscription && cd /opt/remnawave/subscription

cat > docker-compose.yml <<'EOF'
services:
  remnawave-subscription-page:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    restart: always
    env_file:
      - .env
    ports:
      - '127.0.0.1:3010:3010'
    networks:
      - remnawave-network

networks:
  remnawave-network:
    name: remnawave-network
    external: true
EOF

cat > .env <<EOF
APP_PORT=3010
REMNAWAVE_PANEL_URL=http://remnawave:3000
REMNAWAVE_API_TOKEN=${TOKEN}
TRUST_PROXY=1
EOF
chmod 600 .env

docker compose up -d
sleep 3
docker compose logs --tail=30

echo
echo "Проверьте SUB_PUBLIC_DOMAIN в /opt/remnawave/.env (должен быть ваш sub-домен),"
echo "затем: cd /opt/remnawave && docker compose down remnawave && docker compose up -d"
