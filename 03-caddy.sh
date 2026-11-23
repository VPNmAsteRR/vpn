#!/usr/bin/env bash
# Caddy как reverse-proxy: TLS-сертификаты автоматически (Let's Encrypt).
# Использование: bash 03-caddy.sh panel.example.com sub.example.com
set -euo pipefail

PANEL_DOMAIN="${1:?Укажите домен панели}"
SUB_DOMAIN="${2:-$PANEL_DOMAIN}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите от root" >&2
  exit 1
fi

# Панель и subscription-page живут в этой сети
docker network create remnawave-network >/dev/null 2>&1 || true

mkdir -p /opt/remnawave/caddy && cd /opt/remnawave/caddy

cat > Caddyfile <<EOF
{
    email admin@${PANEL_DOMAIN#*.}
}

https://${PANEL_DOMAIN} {
    encode zstd gzip
    header {
        Strict-Transport-Security "max-age=31536000;"
        X-Content-Type-Options "nosniff"
        -Server
    }
    reverse_proxy * http://remnawave:3000
}

https://${SUB_DOMAIN} {
    encode zstd gzip
    reverse_proxy * http://remnawave-subscription-page:3010
}

# Заглушка для всех прочих SNI: сканер видит пустой 204
:443 {
    tls internal
    respond 204
}
EOF

cat > docker-compose.yml <<'EOF'
services:
  caddy:
    image: caddy:2.9
    container_name: caddy
    hostname: caddy
    restart: always
    ports:
      - '0.0.0.0:80:80'
      - '0.0.0.0:443:443'
    networks:
      - remnawave-network
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-ssl-data:/data

networks:
  remnawave-network:
    name: remnawave-network
    external: true

volumes:
  caddy-ssl-data:
    name: caddy-ssl-data
EOF

docker compose up -d
sleep 3
docker compose logs --tail=30

echo
echo "Проверка: curl -I https://${PANEL_DOMAIN}"
