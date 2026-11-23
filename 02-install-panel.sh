#!/usr/bin/env bash
# Установка Remnawave Panel.
# Использование: bash 02-install-panel.sh panel.example.com sub.example.com
set -euo pipefail

DOMAIN="${1:?Укажите домен панели, например panel.example.com}"
SUB_DOMAIN="${2:-$DOMAIN}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите от root: sudo bash $0 $*" >&2
  exit 1
fi

set_env() { # set_env KEY VALUE
  local key="$1" value="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

echo "==> Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
docker --version
docker compose version

echo "==> Файлы панели"
mkdir -p /opt/remnawave && cd /opt/remnawave
curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml
curl -fsSL -o .env            https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample

echo "==> Секреты"
sed -i "s/^APP_SECRET=.*/APP_SECRET=$(openssl rand -hex 64)/" .env
sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" .env
sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" .env

PW="$(openssl rand -hex 24)"
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${PW}/" .env
sed -i "s|^\(DATABASE_URL=\"postgresql://postgres:\)[^@]*\(@.*\)|\1${PW}\2|" .env

echo "==> Домены"
set_env FRONT_END_DOMAIN "$DOMAIN"
set_env SUB_PUBLIC_DOMAIN "$SUB_DOMAIN"

# Панель слушает только localhost — наружу отдаём через Caddy.
grep -q "127.0.0.1:3000:3000" docker-compose.yml || \
  echo "ВНИМАНИЕ: в docker-compose.yml порт панели не 127.0.0.1:3000 — проверьте вручную." >&2

echo "==> Запуск"
docker compose up -d
sleep 8
docker compose ps
docker compose logs --tail=40 remnawave || true

echo
echo "Панель: https://${DOMAIN} (после настройки reverse-proxy, шаг 03-caddy.sh)"
echo "Если TLS ещё не настроен: bash 03-caddy.sh ${DOMAIN} ${SUB_DOMAIN}"
