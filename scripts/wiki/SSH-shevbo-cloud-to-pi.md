# SSH без пароля: shevbo-cloud → shevbo-pi

На **shevbo-cloud** создан отдельный ключ **`~/.ssh/id_ed25519_shevbo_pi`** (комментарий `shevbo-cloud-to-shevbo-pi`), только для входа на Raspberry Pi — основной ключ не трогаем.

## 1. Адрес Pi

VPS в облаке **не видит** домашний `*.local`. Нужен один из вариантов:

- **Tailscale / ZeroTier / WireGuard** — IP из VPN (часто `100.x.x.x`);
- **Публичный IP** дома + проброс порта **22** на Pi;
- **SSH через другой хост** (ProxyJump), если так настроена сеть.

В **`~/.ssh/config`** на shevbo-cloud замени **`HostName 192.0.2.1`** (заглушка из документации) на реальный хост/IP.

Фрагмент конфига лежит в репозитории: `scripts/ssh/shevbo-cloud-ssh-config-pi`.

## 2. Установить pubkey на Pi

Публичный ключ: **`~/.ssh/id_ed25519_shevbo_pi.pub`** на shevbo-cloud.

**Вариант A — с shevbo-cloud (один раз с паролем пользователя Pi):**

```bash
# на shevbo-cloud
~/bin/shevbo-cloud-install-pi-key.sh shevbo@<IP_или_DNS_Pi>
```

**Вариант B — вручную на Pi:**

```bash
# на Pi под пользователем shevbo
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys   # вставить одной строкой содержимое id_ed25519_shevbo_pi.pub с VPS
chmod 600 ~/.ssh/authorized_keys
```

Содержимое `.pub` с VPS можно вывести: `cat ~/.ssh/id_ed25519_shevbo_pi.pub` (скопировать в буфер).

## 3. Проверка

На **shevbo-cloud**:

```bash
ssh shevbo-pi 'hostname && uname -a'
```

Должно подключаться **без пароля**.

Проверка в режиме, близком к **OpenClaw `exec`** (без запроса пароля, с таймаутом):

```bash
bash scripts/ssh/verify-shevbo-pi-ssh-batchmode.sh
```

Если здесь ошибка **`Permission denied (publickey,password)`**, агент из чата **не сможет** залогиниться по SSH с паролем — настройте ключи (`ssh-copy-id` / `shevbo-cloud-install-pi-key.sh`) или используйте инструмент **`nodes`** для команд на Pi.

## 4. Разработчики и QA

- Доступ с **рабочих машин** на Pi — отдельно (свои ключи или общий bastion). Связка **cloud → Pi** нужна для CI, деплоя, скриптов с VPS.
- Не копируй **приватный** ключ `id_ed25519_shevbo_pi` с сервера; только распространяй **публичный** на Pi.

## 5. Файлы в репозитории

| Файл | Назначение |
|------|------------|
| `scripts/ssh/shevbo-cloud-ssh-config-pi` | Шаблон `Host shevbo-pi` |
| `scripts/ssh/shevbo-cloud-install-pi-key.sh` | `ssh-copy-id` с нужным `-i` |

---

*После смены IP Pi (DHCP) обнови `HostName` в `~/.ssh/config` на shevbo-cloud.*

---

См. также: **[OpenClaw: Pi как remote-node к шлюзу в облаке](OpenClaw-Pi-remote-node-WireGuard.md)** (WG / wss / SSH-туннель).
