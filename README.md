# xrayCli

CLI-установщик для быстрого развёртывания **Xray VPN** на **Debian 13** (Trixie / bookworm).

Автоматически устанавливает `xray-core` и `nginx`, генерирует ключи и UUID, создаёт конфигурацию и сохраняет готовые ссылки `vless://` и Reality client JSON для клиентов.

## Режимы

| Режим | Флаг `--mode` | Описание |
|-------|---------------|----------|
| VLESS + WebSocket + TLS | `vless-ws` | Домен + Let's Encrypt + nginx → xray |
| VLESS + Reality | `vless-reality` | Маскировка под чужой SNI, без своего домена |
| Комбо | `combo` | Оба режима на порту 443 через nginx stream |

## Требования

- Debian 13 (trixie) или bookworm
- root-доступ
- Для VLESS-WS: домен с A/AAAA записью на IP сервера
- Открытые порты 80 и 443 (для WS/combo)

## Быстрый старт

```bash
git clone <repo-url> xrayCli
cd xrayCli
chmod +x install.sh bin/xray-cli
sudo ./install.sh
```

Интерактивный установщик спросит режимы и домен.

### Неинтерактивно

```bash
# Только VLESS через домен
sudo ./install.sh --non-interactive --yes \
  --mode vless-ws --domain vpn.example.com --email admin@vpn.example.com

# Только Reality
sudo ./install.sh --non-interactive --yes --mode vless-reality

# Reality по эталонному клиентскому JSON
sudo ./install.sh --non-interactive --yes \
  --mode vless-reality \
  --reality-reference-json /path/to/test.json

# Комбо
sudo ./install.sh --non-interactive --yes \
  --mode combo --domain vpn.example.com --email admin@vpn.example.com
```

### Dry-run

```bash
sudo ./install.sh --dry-run --mode combo --domain vpn.example.com --yes
```

## Результат установки

| Файл | Содержимое |
|------|------------|
| `/etc/xray-cli/client-links.txt` | Ссылки `vless://` для импорта в клиент |
| `/etc/xray-cli/client-reality.json` | Готовый Reality client JSON с новым `publicKey` сервера |
| `/etc/xray-cli/state.env` | UUID, ключи, параметры (chmod 600) |
| `/usr/local/etc/xray/config.json` | Конфигурация xray |

## Reverse Engineering from Client JSON

Если у вас уже есть стабильный клиентский Reality-конфиг, его можно использовать как эталон:

```bash
sudo ./install.sh --mode vless-reality --yes --non-interactive \
  --reality-reference-json /path/to/test.json
```

`xrayCli` импортирует из него наблюдаемые параметры, например `address`, `serverName`, `fingerprint`, `flow` и reference `publicKey`.

Важно:

- `privateKey` удалённого сервера из клиентского JSON восстановить нельзя.
- `UUID` и `shortId` для нашего сервера и клиентских артефактов генерируются локально как раньше.
- `xrayCli` всегда генерирует свою пару `x25519` для нового сервера.
- В ссылку `vless://` и в `/etc/xray-cli/client-reality.json` записывается уже новый локально сгенерированный `publicKey`.
- Импортированный `publicKey` сохраняется только как reference-значение для сверки и диагностики.

## Управление после установки

```bash
sudo xray-cli status
sudo xray-cli links
sudo xray-cli test-config
sudo xray-cli uninstall
```

Установите `bin/xray-cli` в PATH или создайте symlink:

```bash
sudo ln -sf "$(pwd)/bin/xray-cli" /usr/local/bin/xray-cli
```

## Разработка

```bash
make lint    # shellcheck
make test    # bats или fallback-тесты
```

## Документация

Подробности: [docs/install.md](docs/install.md)

## Лицензия

MIT
