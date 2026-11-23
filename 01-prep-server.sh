#!/usr/bin/env bash
# Базовая подготовка любого сервера (панель или нода).
# Запускать от root на Ubuntu 22.04/24.04 или Debian 12.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите от root: sudo bash $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Пакеты"
apt-get update -y
apt-get upgrade -y
apt-get install -y ca-certificates curl jq ufw fail2ban unattended-upgrades \
                   htop unzip nano chrony logrotate

echo "==> Swap 2G (если ещё нет)"
if ! swapon --show | grep -q '/swapfile'; then
  if ! fallocate -l 2G /swapfile 2>/dev/null; then
    dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  fi
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
cat > /etc/sysctl.d/99-swap.conf <<'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

echo "==> Сеть: BBR + fastopen"
cat > /etc/sysctl.d/99-net.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_fastopen=3
net.ipv4.ip_forward=1
fs.file-max=1000000
EOF
sysctl --system >/dev/null

echo "==> Фаервол"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
ufw status verbose

echo "==> Автообновления безопасности"
dpkg-reconfigure -f noninteractive unattended-upgrades || true

echo "==> Часовой пояс UTC"
timedatectl set-timezone UTC || true

echo
echo "Готово. Проверка:"
free -h | head -2
df -h / | tail -1
sysctl net.ipv4.tcp_congestion_control
