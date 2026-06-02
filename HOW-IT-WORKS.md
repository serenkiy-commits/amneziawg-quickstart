# Что под капотом

Если интересно, что именно делает `install.sh` — вот пошаговый разбор. Все шаги легко повторить руками, скрипт ничего секретного не прячет.

## 1. Ставит пакеты AmneziaWG из официального PPA

```bash
add-apt-repository -y ppa:amnezia/ppa
apt-get update
apt-get install -y amneziawg amneziawg-tools qrencode iptables
```

`amneziawg` — модуль ядра (форк WireGuard с обфускацией).
`amneziawg-tools` — утилиты `awg` и `awg-quick` (форк `wg`, `wg-quick`).

## 2. Включает IP forwarding

Чтобы VPS пересылал трафик из туннеля в интернет:

```bash
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-amneziawg.conf
sysctl --system
```

## 3. Генерирует ключи сервера

```bash
awg genkey | tee server_private.key | awg pubkey > server_public.key
```

Приватный ключ остаётся в `/etc/amnezia/amneziawg/server_private.key`, права `600`.

## 4. Генерирует параметры обфускации

Это то, чем AmneziaWG отличается от обычного WireGuard:

- `Jc`, `Jmin`, `Jmax` — параметры джиттера (случайные паузы между пакетами рукопожатия)
- `S1`, `S2` — длины случайных байт, добавляемых в начало пакета
- `H1`, `H2`, `H3`, `H4` — magic-числа в заголовках пакетов (заменяют стандартные WG-маркеры)

Для DPI это выглядит как случайный UDP-шум — он не может опознать сигнатуру WireGuard.

**Важно:** `H1..H4` у каждого сервера свои (генерятся случайно). Поэтому два разных VPS с этим скриптом — две независимые сети, не палящие друг друга.

## 5. Создаёт конфиг сервера

`/etc/amnezia/amneziawg/awg0.conf`:

```ini
[Interface]
Address = 10.9.0.1/24
ListenPort = 443
PrivateKey = <сгенерированный приватный ключ>

Jc = 7
Jmin = 50
Jmax = 1000
S1 = 49
S2 = 79
H1 = 385245399
H2 = 329261243
H3 = 638439461
H4 = 58332419

PostUp = iptables -A FORWARD -i %i -j ACCEPT; ...
PostDown = iptables -D FORWARD -i %i -j ACCEPT; ...
```

`PostUp`/`PostDown` правила NAT'ят трафик из подсети `10.9.0.0/24` в интернет через основной интерфейс (`eth0` или как он у тебя называется).

## 6. Поднимает туннель

```bash
awg-quick up awg0
systemctl enable awg-quick@awg0   # автозапуск после ребута
```

После этого `awg show` показывает интерфейс `awg0`, слушающий `443/UDP`.

## 7. Добавляет первого пира

Скрипт `add-peer.sh` для каждого устройства:

1. Генерит **приватный ключ клиента** + **публичный ключ клиента** + **preshared key** (общий секрет для пары сервер-клиент).
2. Дописывает `[Peer]` в `awg0.conf` сервера:
   ```ini
   [Peer]
   # my-phone
   PublicKey = <публичный ключ клиента>
   PresharedKey = <psk>
   AllowedIPs = 10.9.0.2/32
   ```
3. Применяет изменение на лету:
   ```bash
   awg set awg0 peer <pub> preshared-key <psk-file> allowed-ips 10.9.0.2/32
   ```
   Без рестарта туннеля — остальные пиры не отваливаются.
4. Создаёт клиентский конфиг `/root/vpn-clients/my-phone.conf` с тем же набором `Jc/S1/H1` что и сервер (иначе handshake не сойдётся) + endpoint = `<публичный-ip-сервера>:443`.
5. Рисует QR в терминале и сохраняет `.png` для шеринга.

## 8. Удаление пира

```bash
awg set awg0 peer <pub> remove   # снять с туннеля
# + удалить блок [Peer] из awg0.conf
# + удалить /root/vpn-clients/<имя>.conf
```

## Карта файлов

| Путь | Что |
|------|-----|
| `/etc/amnezia/amneziawg/awg0.conf` | Главный конфиг + список пиров |
| `/etc/amnezia/amneziawg/.params` | Параметры обфускации (источник правды для клиентских конфигов) |
| `/etc/amnezia/amneziawg/server_*.key` | Ключи сервера |
| `/root/vpn-clients/<имя>.conf` | Готовые конфиги для устройств |
| `/root/vpn-clients/<имя>.png` | QR-коды |
| `/usr/local/sbin/amneziawg-add-peer` | Команда добавления (копия `add-peer.sh`) |
| `/usr/local/sbin/amneziawg-remove-peer` | Команда удаления |
| `/etc/systemd/system/multi-user.target.wants/awg-quick@awg0.service` | Автозапуск |
| `/etc/sysctl.d/99-amneziawg.conf` | IP forwarding |

## Полезные команды

```bash
sudo awg show                                # кто подключён, handshake, трафик
sudo systemctl status awg-quick@awg0         # состояние сервиса
sudo awg-quick down awg0 && sudo awg-quick up awg0   # перезапуск туннеля
sudo journalctl -u awg-quick@awg0 -n 50      # логи запуска
sudo ss -ulnp | grep 443                     # проверить что порт слушается
```
