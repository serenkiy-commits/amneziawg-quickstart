# AmneziaWG Quickstart

Свой VPN на собственном VPS за 2 минуты. Без подписок, без логов, без посредников.

**AmneziaWG** = WireGuard + обфускация трафика. Под DPI выглядит как случайный шум по UDP-443 (тот же порт, что и HTTPS). Работает там, где обычный WireGuard и OpenVPN блокируются: РФ, Иран, Китай.

## Что получится

- Сервер VPN на твоём VPS, слушает `443/UDP`.
- Подключение с iPhone, Android, Windows, macOS, Linux через приложение **AmneziaVPN**.
- Команды управления одной строкой:
  ```
  sudo amneziawg-add-peer my-laptop      # добавить устройство
  sudo amneziawg-remove-peer my-laptop   # удалить
  sudo awg show                          # кто подключён, сколько трафика
  ```

## Что нужно

1. **VPS** на Ubuntu 22.04 или 24.04. Подойдёт самый дешёвый: 1 CPU / 1 GB RAM / 10 GB диска. Хостеры: Hetzner ($4/мес), Aeza, FirstByte, любой другой.
2. **Локация VPS** там, где нужный тебе интернет: Германия, Нидерланды, США, Финляндия. Не в РФ.
3. **5 минут времени** и SSH-доступ к серверу под `root`.

## Установка — 3 команды

Зайди на свой VPS по SSH (`ssh root@<ip-сервера>`) и выполни:

```bash
apt update && apt install -y git
git clone https://github.com/<your-org>/amneziawg-quickstart.git
sudo bash amneziawg-quickstart/install.sh
```

Скрипт спросит три вещи:
- **Публичный IP** (определит сам, можно подтвердить Enter)
- **UDP-порт** (по умолчанию `443` — лучше оставить, маскируется под HTTPS)
- **Имя первого устройства** (например, `my-phone`)

Через минуту увидишь QR-код прямо в терминале. Это конфиг для твоего первого устройства.

## Подключение устройства

### iPhone / Android

1. Установи приложение **AmneziaVPN**:
   - iPhone: [App Store](https://apps.apple.com/app/amneziavpn/id1600529900)
   - Android: [Google Play](https://play.google.com/store/apps/details?id=org.amnezia.vpn)
2. Открой приложение → плюсик → **Сканировать QR-код** → наведи камеру на QR из терминала VPS.
3. Нажми «Подключить».

Проверь: открой [2ip.ru](https://2ip.ru) — там должен быть IP твоего VPS, а не родной.

### Windows / macOS / Linux

1. Скачай приложение AmneziaVPN: <https://amnezia.org/downloads>
2. Из VPS забери файл конфига:
   ```
   scp root@<ip-сервера>:/root/vpn-clients/my-phone.conf .
   ```
3. В приложении AmneziaVPN → **Импорт конфигурации** → выбери файл.
4. Нажми «Подключить».

> ⚠️ Обычный клиент WireGuard (от wireguard.com) **не подойдёт** — он не понимает обфускацию Jc/S1/H1. Только AmneziaVPN.

## Добавить ещё устройство

На сервере:

```bash
sudo amneziawg-add-peer ноут-жены
sudo amneziawg-add-peer ipad
sudo amneziawg-add-peer друг-петя
```

Каждый раз создаётся новый `.conf` файл и QR в `/root/vpn-clients/`. IP в подсети `10.9.0.0/24` подбирается автоматически (следующий свободный).

## Удалить устройство

```bash
sudo amneziawg-remove-peer ipad
```

Активные сессии остальных пиров не разрываются.

## Посмотреть статус

```bash
sudo awg show
```

Покажет всех подключённых, последний handshake, объём трафика по пирам.

## Что под капотом

Скрипт `install.sh` делает то, что описано в [HOW-IT-WORKS.md](HOW-IT-WORKS.md). Если хочешь понимать что у тебя на сервере — почитай. Все действия легко повторить руками.

## Проблемы

См. [TROUBLESHOOTING.md](TROUBLESHOOTING.md). Самые частые:

- **QR отсканировал, но интернета нет** → у провайдера VPS закрыт `443/UDP`. Поменяй порт: `awg-quick down awg0`, замени `ListenPort` в `/etc/amnezia/amneziawg/awg0.conf` (например, на `51820`), пересоздай пиров.
- **Подключения нет совсем** → проверь firewall провайдера VPS, открыт ли там UDP.
- **На Windows/Mac не импортится** → проверь что ставишь именно **AmneziaVPN**, не WireGuard.

## Удалить всё

```bash
sudo bash amneziawg-quickstart/uninstall.sh
```

## Безопасность

- Все ключи генерятся прямо на твоём VPS. Никто (включая разработчиков этого скрипта) их не видит.
- Параметры обфускации (`H1..H4`) у каждого сервера свои — между разными установками сети не пересекаются.
- Логов трафика **нет**. AmneziaWG ничего не логирует помимо стандартного systemd-журнала (handshake-события).

## Лицензия

MIT. Используй как хочешь.
