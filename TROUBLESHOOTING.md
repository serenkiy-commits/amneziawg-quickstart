# Troubleshooting

Самые частые грабли при первой настройке.

## Подключился, но интернета нет

Симптом: в приложении AmneziaVPN показывает «Подключено», но сайты не открываются.

**Проверь handshake.** На сервере:

```bash
sudo awg show
```

Смотри строку `latest handshake` у твоего пира.

### Handshake `(none)` или старше 3 минут

Пакеты не доходят до сервера. Причина — UDP-порт закрыт на стороне VPS-провайдера или роутера.

- Зайди в панель VPS-провайдера, в раздел **Firewall** / **Security Group**.
- Добавь правило: разрешить **UDP** на порту, который выбрал при установке (по умолчанию `443`).
- На самом VPS проверь, что Ubuntu UFW не блокирует:
  ```bash
  sudo ufw status
  sudo ufw allow 443/udp     # если UFW включён
  ```

### Handshake свежий, но трафика нет

```
transfer: 0 B received, 1.2 MiB sent
```

Туннель есть, но возврат пакетов из интернета не доходит. Скорее всего отвалился NAT.

```bash
sudo iptables -t nat -L POSTROUTING -n -v        # должна быть строка с MASQUERADE
sudo awg-quick down awg0 && sudo awg-quick up awg0   # перечитать PostUp правила
sysctl net.ipv4.ip_forward                       # должно быть = 1
```

Если `ip_forward = 0`:

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-amneziawg.conf
sudo sysctl --system
```

## Handshake свежий, но `2ip.ru` показывает мой родной IP

Туннель работает, но трафик идёт мимо. На клиенте не активирован full-tunnel. Проверь в конфиге `[Peer] AllowedIPs = 0.0.0.0/0` (а не `10.9.0.0/24`).

## Приложение AmneziaVPN не импортит .conf

- Убедись что ставишь **AmneziaVPN**, а не «WireGuard» с того же логотипом.
- Файл должен оканчиваться на `.conf`, не `.txt`.
- На iOS бывает помогает: отправить файл себе в Telegram → открыть из Telegram → «Поделиться» → AmneziaVPN.

## После ребута VPS не работает

```bash
sudo systemctl status awg-quick@awg0
```

Если `inactive` — включи автозапуск:

```bash
sudo systemctl enable --now awg-quick@awg0
```

## Модуль `amneziawg` не загружается

Симптом при `install.sh`:

```
Ядро не поддерживает модуль amneziawg
```

Скорее всего у твоего VPS-провайдера кастомное ядро без headers (типичная история на OpenVZ, не KVM). Решения:

- Пересоздать VPS с **KVM** виртуализацией (не OpenVZ).
- Обновить ядро: `sudo apt install linux-image-generic linux-headers-generic && reboot`.
- Если ничего не помогает — поменять хостера. Hetzner / Aeza / FirstByte все на KVM.

## DPI всё равно режет соединение (RU)

Если ты в РФ и подключение работает первые секунды, а потом обрывается:

1. **Поменяй порт.** 443 может быть под прицелом — попробуй `51820`, `8443`, или произвольный высокий порт.
   ```bash
   sudo awg-quick down awg0
   sudo sed -i 's/^ListenPort = .*/ListenPort = 51820/' /etc/amnezia/amneziawg/awg0.conf
   # На клиенте поменяй Endpoint = <ip>:51820 в .conf
   sudo awg-quick up awg0
   ```
2. **Регенерируй H1..H4.** Если параметры обфускации засветились (например, ты пользовался публичным провайдером AmneziaWG с такими же значениями), сгенерируй новые случайные и поправь сервер + всех клиентов.
3. **Поменяй локацию VPS.** РКН блокирует не сам протокол, а IP-диапазоны популярных хостингов. Маленькие европейские провайдеры (FirstByte, Aeza) живут дольше Hetzner / DigitalOcean.

## Где смотреть логи

```bash
sudo journalctl -u awg-quick@awg0 -n 100      # запуск/остановка туннеля
sudo dmesg | grep -i amnezia                  # модуль ядра
sudo awg show awg0 dump                       # сырое состояние всех пиров
```

## Сделал что-то странное и всё сломал

Снести всё начисто:

```bash
sudo bash amneziawg-quickstart/uninstall.sh
```

И установить заново.
