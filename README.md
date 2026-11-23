# Свой VPN из 5 серверов Hicloud (VLESS + Reality, панель + подписка)

Цель: 5 локаций (DE, FI, NL, PL, US), одна панель, каждому человеку — одна ссылка-подписка,
в клиенте сразу все 5 стран. Протокол — **VLESS + Reality** (XTLS-Vision), потому что
WireGuard/OpenVPN в РФ сейчас режут по DPI, а Reality выглядит как обычный HTTPS к чужому сайту.

## Архитектура

```
                    ┌───────────────────────────────┐
   admin  ─────────▶│  Панель Remnawave (1 сервер)   │  panel.example.com
                    │  + Subscription Page          │  sub.example.com
                    └──────────────┬────────────────┘
                                   │ API (порт 2222, только с IP панели)
        ┌──────────────┬───────────┴───────┬──────────────┐
        ▼              ▼                   ▼              ▼
   node DE :443   node FI :443       node NL :443    node PL :443   node US :443
      (VLESS+Reality, Xray-core, клиентам отдаём через одну подписку)
```

- **Панель** — управление пользователями, нодами, лимитами, подписками. Сама трафик не гоняет.
- **Node** — контейнер с Xray, стоит на каждом из 5 серверов, слушает 443 (Reality).
- **Subscription page** — красивая страница `https://sub.example.com/<uuid>`, отдаёт ссылку-подписку и QR.

## ⚠️ Важно про ваши серверы

Панель Remnawave официально требует **2 ГБ RAM (реком. 4 ГБ) и 20 ГБ диска**.
На скриншоте у серверов ~512 МБ–1 ГБ — этого мало для панели, но **достаточно для ноды**.

Сначала проверьте реальные характеристики (с любого своего компа):

```bash
for ip in <DE_IP> <FI_IP> <NL_IP> <PL_IP> <US_IP>; do
  echo "== $ip"; ssh root@$ip 'free -h | head -2; df -h / | tail -1; nproc'
done
```

Варианты:
1. **Рекомендую:** панель — на отдельном дешёвом VPS 2 ГБ/20 ГБ (или докупить больший тариф в Hicloud),
   а эти 5 — только ноды. Так надёжнее и панель не умрёт от OOM.
2. Без денег: панель на самом «жирном» сервере + swap 2 ГБ (скрипт `01-prep-server.sh` его создаёт).
   Работает, но при наплыве пользователей может подтормаживать.
3. Совсем без запаса: вместо Remnawave поставить **Marzban** (ему хватает 512 МБ–1 ГБ, тоже есть ноды и подписка).
   Тогда этот гайд не подходит, скажите — переделаю.

## Что нужно заранее

- Домен (например `example.com`) и доступ к DNS (Cloudflare удобнее всего).
- Две A-записи:
  - `panel.example.com` → IP сервера с панелью
  - `sub.example.com`   → IP сервера с панелью (тот же)
- SSH-доступ root ко всем 5 серверам.
- 30–40 минут.

> Домены для панели/подписки лучше **не** светить в РФ-блоклистах: берите нейтральное имя,
> Cloudflare-прокси (оранжевая тучка) для `panel.` и `sub.` можно оставить включённым.

## Порядок действий

### Шаг 0. Подготовка всех 5 серверов

Скопируйте папку `vpn/` на каждый сервер (или просто вставьте скрипт) и выполните от root:

```bash
bash 01-prep-server.sh
```

Скрипт: обновляет пакеты, ставит Docker-зависимости, создаёт swap 2 ГБ, включает BBR,
настраивает ufw (22/80/443) и fail2ban.

### Шаг 1. Панель (на выбранном сервере с панелью)

```bash
bash 02-install-panel.sh panel.example.com sub.example.com
```

Затем reverse-proxy с автоматическим TLS:

```bash
bash 03-caddy.sh panel.example.com sub.example.com
```

Открываете `https://panel.example.com` → при первом входе панель предложит создать администратора
(onboarding). Пароль — сложный, 2FA включить.

### Шаг 2. Subscription page (на сервере с панелью)

1. В панели: **Settings → API Tokens → Create token**, скопируйте.
2. На сервере:

```bash
bash 04-sub-page.sh <ВАШ_API_ТОКЕН>
```

3. В `/opt/remnawave/.env` проверьте, что `SUB_PUBLIC_DOMAIN=sub.example.com`, и перезапустите панель:

```bash
cd /opt/remnawave && docker compose down remnawave && docker compose up -d
```

### Шаг 3. Ноды на 4–5 серверах

1. В панели: **Nodes → Management → «+»**.
2. Заполните: имя (`germany-d19`), адрес (`de19.hicloud.net` или IP), порт `2222`, страну.
3. Нажмите **Copy docker-compose.yml** — панель сгенерирует compose с `SECRET_KEY`.
4. На сервере ноды:

```bash
bash 05-install-node.sh 2222 '<SECRET_KEY_ИЗ_ПАНЕЛИ>' '<IP_ПАНЕЛИ>'
```

5. Вернитесь в панель → **Next** → выберите Config Profile → **Create**.

Повторите для всех 5 серверов. Порт `2222` должен быть открыт **только для IP панели**.

### Шаг 4. Профиль Xray (VLESS + Reality)

**Config Profiles → Create**. Готовый шаблон — `config-profile-reality.json` в этой папке.

Сгенерировать пару ключей Reality:

```bash
docker run --rm ghcr.io/xtls/xray-core:latest x25519
```

- `privateKey` (Private key) → в профиль;
- `password` (Public key) → понадобится при создании Host в панели;
- `dest`/`serverNames` — сайт с TLS 1.3, который не заблокирован в РФ и не принадлежит вам
  (например `www.microsoft.com:443`, `www.apple.com:443`, `dl.google.com:443`).
  Не берите `cloudflare.com`, `github.com` и прочее, что любят перебирать сканеры.

### Шаг 5. Hosts (точки входа)

**Hosts → Create** для каждой ноды:

| Поле | Значение |
|---|---|
| Remark | 🇩🇪 Личный · Германия |
| Address | домен/IP ноды |
| Port | 443 |
| Sni | `www.microsoft.com` (тот же, что в профиле) |
| Public key | из `x25519` |
| Short ID | один из `shortIds` профиля |
| Fingerprint | `chrome` |
| Flow | `xtls-rprx-vision` |

Именно Hosts попадают в подписку — 5 записей = 5 стран в клиенте.

### Шаг 6. Пользователи и подписка

**Users → Create**: имя, лимит устройств (HWID), срок, лимит трафика.
На карточке пользователя — **Subscription URL** вида `https://sub.example.com/<uuid>`.

Клиенты (все умеют подписку и VLESS Reality):
- iOS — **Happ**, **Streisand**, **FoXray**
- Android — **Happ**, **v2rayNG**, **NekoBox**
- Windows/macOS — **Hiddify**, **NekoRay**, **Happ**
- Роутер — **Keenetic/OpenWrt** через Xray/sing-box (подписку можно развернуть в конфиг)

Человек вставляет ссылку → получает 5 локаций → переключает кнопкой.

### Шаг 7. Чтобы реально обходило блокировки

- Порт **443**, `flow: xtls-rprx-vision`, fingerprint `chrome` — обязательно.
- `dest`/`SNI` — живой популярный сайт с TLS 1.3, не из чёрных списков РКН.
- На клиенте включите **routing**: RU-домены и RU-IP — напрямую (`direct`), остальное — в прокси.
  Так меньше заметно и быстрее (в Happ есть готовые пресеты, в v2rayNG — «Russia direct»).
- Не давайте доступ незнакомым и не публикуйте ссылку: одна утёкшая ссылка = нода в блоклисте.
- Держите по 1–2 резервные ноды/профиля на разных SNI.

## Обслуживание

```bash
# обновить панель
cd /opt/remnawave && docker compose pull && docker compose up -d

# обновить ноду
cd /opt/remnanode && docker compose pull && docker compose up -d

# бэкап БД панели
docker exec remnawave-db pg_dump -U postgres postgres | gzip > /root/panel-$(date +%F).sql.gz

# логи
cd /opt/remnawave && docker compose logs -f --tail=100
```

Панель раз в неделю бэкапить обязательно: там все ключи и пользователи.

## Легально/безопасно

- Не занимайтесь рассылкой спама, ботнетами, торрентами с серверов — Hicloud заблокирует аккаунт.
- Свои серверы = вы видите IP пользователей. Скажите близким, что логи не ведутся (и правда не ведите).
- Панель и API-токен — только по HTTPS и только для себя.
