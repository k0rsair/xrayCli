# План реализации: CLI-установщик Xray VPN для Debian 13

Branch: feature/xray-vpn-installer-cli
Created: 2026-06-12

## Settings
- Testing: yes
- Logging: verbose
- Docs: yes

## Roadmap Linkage
Milestone: "none"
Rationale: ROADMAP.md отсутствует — связь с milestone пропущена.

## Обзор

Greenfield-проект: bash CLI для автоматической установки **xray-core** и **nginx** на Debian 13 (Trixie). Скрипт интерактивно спрашивает домен и выбранные режимы, генерирует ключи/UUID, пишет конфиги, поднимает systemd-сервисы и сохраняет готовые ссылки подключения в файл.

### Поддерживаемые режимы (включаются/отключаются при установке)

| Режим | Код | Порт | Nginx | Домен пользователя | Описание |
|-------|-----|------|-------|-------------------|----------|
| VLESS + WebSocket + TLS | `vless-ws` | 443 | Да (TLS termination) | Обязателен | Основной сценарий: nginx проксирует `wss` на локальный xray |
| VLESS + Reality | `vless-reality` | 443* | Нет** | Не нужен (маскировка под чужой SNI) | `flow: xtls-rprx-vision`, ключи x25519 |
| Комбо VLESS-WS + Reality | `combo` | 443 | stream (SNI routing) | Обязателен для WS-части | nginx `stream` + `ssl_preread` маршрутизирует по SNI |

\* При комбо Reality и WS делят 443 через nginx stream.  
\** При одиночном Reality nginx не обязателен; при комбо nginx нужен для WS и маршрутизации.

### Целевая структура проекта

```
xrayCli/
├── install.sh              # точка входа (curl | bash или ./install.sh)
├── bin/xray-cli            # обёртка для post-install: status, show-links, uninstall
├── lib/
│   ├── common.sh           # логирование, проверки ОС/root, утилиты
│   ├── prompts.sh          # интерактивное меню режимов
│   ├── install-deps.sh     # apt: nginx, certbot, curl, jq, uuid-runtime
│   ├── install-xray.sh     # официальный XTLS install-release.sh
│   ├── ssl.sh              # certbot + копирование сертификатов для xray
│   ├── crypto.sh           # xray uuid, xray x25519, shortId
│   ├── config-vless-ws.sh  # шаблон inbound VLESS-WS
│   ├── config-reality.sh   # шаблон inbound VLESS-Reality
│   ├── config-merge.sh     # сборка единого config.json
│   ├── nginx-vless.sh      # site + stream конфиги nginx
│   ├── link-builder.sh     # генерация vless:// URI
│   └── service.sh          # systemctl, firewall hints
├── templates/
│   ├── xray-base.json.tpl
│   ├── nginx-site.conf.tpl
│   └── nginx-stream.conf.tpl
├── tests/
│   ├── shellcheck.sh
│   └── bats/               # unit-тесты функций (mock окружение)
├── docs/
│   └── install.md
├── README.md
└── Makefile                # lint, test, package
```

### Ключевые технические решения

1. **Установка xray**: официальный скрипт `https://github.com/XTLS/Xray-install/raw/main/install-release.sh @ install` → бинарь `/usr/local/bin/xray`, конфиг `/usr/local/etc/xray/config.json`.
2. **Генерация секретов**: `xray uuid`, `xray x25519`; shortId — случайная hex-строка чётной длины ≤16.
3. **VLESS-WS**: xray слушает `127.0.0.1:<WS_PORT>` (по умолчанию 10000), path `/xray-ws`; nginx на 443 терминирует TLS (Let's Encrypt) и `proxy_pass` WebSocket.
4. **Reality**: xray слушает `0.0.0.0:443`; `dest` и `serverNames` — из списка популярных SNI (www.microsoft.com, learn.microsoft.com и т.д.) с выбором в интерактиве; fingerprint `chrome` или `random`.
5. **Комбо**: nginx `stream { ssl_preread on; }` — SNI домена пользователя → nginx http (WS), SNI Reality → upstream xray:443.
6. **Выходные файлы**:
   - `/etc/xray-cli/state.env` — UUID, ключи, порты, выбранные режимы (права 600)
   - `/etc/xray-cli/client-links.txt` — готовые `vless://` ссылки (права 600)
   - Дублирование в stdout в конце установки
7. **Логирование**: `LOG_LEVEL=DEBUG|INFO|WARN|ERROR`, формат `[xray-cli.module] message {key=value}`.
8. **Идемпотентность**: повторный запуск с флагом `--reconfigure` пересобирает конфиги; без флага — предупреждение если xray уже установлен.

### Зависимости Debian 13

```bash
apt install -y curl jq nginx libnginx-mod-stream certbot python3-certbot-nginx ufw
```

## Commit Plan

- **Commit 1** (после задач 1–3): `feat: add project skeleton and core installer libraries`
- **Commit 2** (после задач 4–6): `feat: implement VLESS-WS and Reality config generators`
- **Commit 3** (после задач 7–9): `feat: add nginx/ssl integration and client link output`
- **Commit 4** (после задач 10–12): `test: add shellcheck and bats tests with docs`

## Tasks

### Phase 1: Каркас и инфраструктура

- [x] **Task 1: Инициализация репозитория и точка входа**
  - Создать `install.sh`, `bin/xray-cli`, `lib/common.sh`, `README.md`, `.gitignore`, `Makefile`.
  - `install.sh`: парсинг флагов `--help`, `--non-interactive`, `--mode vless-ws|vless-reality|combo`, `--domain`, `--yes`, `--reconfigure`, `--dry-run`.
  - `common.sh`: `log_debug/info/warn/error`, проверка `EUID=0`, проверка Debian ( `/etc/os-release`, версия ≥ 13 или bookworm/trixie), `require_cmd`, `run_cmd` с dry-run.
  - **LOGGING**: каждая публичная функция — `log_debug` на входе с аргументами (без секретов), `log_info` на успехе, `log_error` с `exit 1` при фатальных ошибках.
  - Файлы: `install.sh`, `lib/common.sh`, `README.md`, `Makefile`, `.gitignore`

- [x] **Task 2: Интерактивные промпты и выбор режимов**
  - `lib/prompts.sh`: меню чекбоксов — «VLESS через домен (WebSocket+TLS)», «VLESS Reality», с валидацией (хотя бы один режим; для WS — запрос домена).
  - Валидация домена: FQDN regex, DNS A/AAAA lookup с предупреждением если IP не совпадает с сервером.
  - Для Reality: выбор `dest` SNI из пресетов + опция ввести свой.
  - Сохранение ответов в переменные `ENABLE_VLESS_WS`, `ENABLE_REALITY`, `DOMAIN`, `REALITY_DEST`.
  - **LOGGING**: `log_debug` выбранных флагов (домен — да, UUID/ключи — нет).
  - Файлы: `lib/prompts.sh`
  - Зависит от: Task 1

- [x] **Task 3: Установка зависимостей и xray-core**
  - `lib/install-deps.sh`: `apt update`, установка пакетов, проверка `nginx -v`, наличие `stream` модуля.
  - `lib/install-xray.sh`: вызов официального install script; проверка `xray version`; не переустанавливать если уже есть (unless `--reconfigure`).
  - **LOGGING**: `log_info` версии nginx/xray после установки; `log_debug` stdout/stderr install script.
  - Файлы: `lib/install-deps.sh`, `lib/install-xray.sh`
  - Зависит от: Task 1

### Phase 2: Криптография и шаблоны конфигов

- [x] **Task 4: Модуль генерации секретов**
  - `lib/crypto.sh`: `gen_uuid()` → `xray uuid`; `gen_x25519()` → parse private/public из `xray x25519`; `gen_short_id()` → random hex 8 chars.
  - Единая функция `persist_secrets()` пишет `/etc/xray-cli/state.env` (chmod 600).
  - **LOGGING**: логировать факт генерации, НЕ логировать значения ключей (только `uuid=***`).
  - Файлы: `lib/crypto.sh`
  - Зависит от: Task 3

- [x] **Task 5: Генератор конфига VLESS + WebSocket + TLS**
  - `lib/config-vless-ws.sh` + `templates/xray-base.json.tpl`: inbound на `127.0.0.1:WS_PORT`, protocol vless, ws path `/xray-ws`, decryption none.
  - Outbounds: freedom + blackhole; routing базовый.
  - Параметры: `DOMAIN`, `UUID`, `WS_PORT` (default 10000), `WS_PATH`.
  - **LOGGING**: `log_debug` путь к сгенерированному JSON; `log_info` тег inbound.
  - Файлы: `lib/config-vless-ws.sh`, `templates/xray-base.json.tpl`
  - Зависит от: Task 4

- [x] **Task 6: Генератор конфига VLESS + Reality**
  - `lib/config-reality.sh`: inbound `0.0.0.0:443`, security reality, flow `xtls-rprx-vision`, realitySettings (dest, serverNames, privateKey, shortIds).
  - Интерактивный выбор fingerprint.
  - **LOGGING**: аналогично Task 5; при конфликте порта 443 с WS — `log_warn` и делегировать в Task 7.
  - Файлы: `lib/config-reality.sh`
  - Зависит от: Task 4

### Phase 3: Nginx, SSL и сборка

- [x] **Task 7: Слияние конфигов и режим combo**
  - `lib/config-merge.sh`: объединение inbounds из WS и Reality в один `config.json`; `xray run -test -config` для валидации.
  - Логика портов:
    - только WS → xray localhost, nginx :443
    - только Reality → xray :443
    - combo → Reality на localhost:REALITY_PORT (напр. 10443), nginx stream маршрутизирует по SNI
  - **LOGGING**: `log_info` итоговая схема портов; `log_error` при fail `xray -test`.
  - Файлы: `lib/config-merge.sh`
  - Зависит от: Task 5, Task 6

- [x] **Task 8: SSL (certbot) и конфигурация nginx**
  - `lib/ssl.sh`: `certbot certonly --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN` (email запросить); cron renew hook копирует certs в `/usr/local/etc/xray/` если нужно.
  - `lib/nginx-vless.sh` + templates: HTTP→HTTPS redirect; `location /xray-ws` с websocket headers; decoy `location /` — статическая заглушка `/var/www/xray-cli/index.html`.
  - Для combo: `templates/nginx-stream.conf.tpl` с `map $ssl_preread_server_name`.
  - **LOGGING**: `log_info` срок действия сертификата; `log_debug` пути fullchain/privkey.
  - Файлы: `lib/ssl.sh`, `lib/nginx-vless.sh`, `templates/nginx-site.conf.tpl`, `templates/nginx-stream.conf.tpl`
  - Зависит от: Task 7

- [x] **Task 9: Генерация клиентских ссылок и сохранение в файл**
  - `lib/link-builder.sh`:
    - WS: `vless://UUID@DOMAIN:443?encryption=none&security=tls&type=ws&host=DOMAIN&path=%2Fxray-ws#vless-ws`
    - Reality: `vless://UUID@SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=SNI&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp#vless-reality`
  - Запись в `/etc/xray-cli/client-links.txt` + вывод в терминал.
  - Определение `SERVER_IP` через `curl -4s ifconfig.me` с fallback.
  - **LOGGING**: `log_info` путь к файлу ссылок; не логировать полные URI в DEBUG (только префикс).
  - Файлы: `lib/link-builder.sh`
  - Зависит от: Task 7, Task 8

### Phase 4: Сервисы, CLI и качество

- [x] **Task 10: Запуск сервисов и post-install CLI**
  - `lib/service.sh`: `systemctl enable --now nginx xray`; проверка `systemctl is-active`; подсказки `ufw allow 443/tcp`, `80/tcp`.
  - `bin/xray-cli`: подкоманды `status`, `links`, `uninstall`, `test-config`.
  - Финальный summary banner в `install.sh`.
  - **LOGGING**: `log_info` статус каждого unit; `log_error` при failed start с `journalctl -u xray -n 20`.
  - Файлы: `lib/service.sh`, `bin/xray-cli`, правки `install.sh`
  - Зависит от: Task 9

- [x] **Task 11: Тесты (shellcheck + bats)**
  - `tests/shellcheck.sh`: shellcheck всех `*.sh`.
  - `tests/bats/`: тесты `link-builder` (mock), `config-merge` (golden file), `prompts` validation domain.
  - `Makefile` targets: `make lint`, `make test`.
  - CI-friendly: тесты не требуют root при `BATS_TEST_MODE=1`.
  - **LOGGING**: в тестах не требуется production logging; проверить что functions не падают без `/usr/local/bin/xray` (mock).
  - Файлы: `tests/shellcheck.sh`, `tests/bats/*.bats`, `Makefile`
  - Зависит от: Task 10

- [x] **Task 12: Документация**
  - `README.md`: быстрый старт (`curl -fsSL ... | bash`), таблица режимов, требования (Debian 13, root, домен → DNS), примеры флагов.
  - `docs/install.md`: детали портов, combo-схема (mermaid), troubleshooting, renew SSL, ручное добавление клиента.
  - **LOGGING**: n/a (документация).
  - Файлы: `README.md`, `docs/install.md`
  - Зависит от: Task 10

## Риски и митигация

| Риск | Митигация |
|------|-----------|
| Конфликт порта 443 при combo | nginx stream + Reality на внутреннем порту |
| DNS домена не указывает на сервер | предупреждение + опция продолжить |
| certbot rate limit | проверка существующего сертификата перед запросом |
| Нет модуля stream в nginx | `libnginx-mod-stream` в deps, проверка при старте |
| Утечка секретов в логи | маскирование в `log_*`, state.env 600 |

## Пример интерактивного сценария

```
$ sudo ./install.sh

=== Xray CLI Installer (Debian 13) ===

Выберите режимы (можно несколько):
  [x] VLESS + WebSocket + TLS (требуется домен)
  [x] VLESS + Reality
  [ ] Только Reality

Введите домен для VLESS-WS: vpn.example.com
Reality dest SNI [1] www.microsoft.com [2] learn.microsoft.com [3] свой: 1

Установка зависимостей... OK
Установка xray-core v25.x.x... OK
Получение SSL для vpn.example.com... OK
Генерация конфигурации... OK
Запуск сервисов... OK

Ссылки сохранены: /etc/xray-cli/client-links.txt

[vless-ws]
vless://a1b2c3...@vpn.example.com:443?...

[vless-reality]
vless://a1b2c3...@203.0.113.1:443?...
```

## Критерии готовности (Definition of Done)

- [x] `./install.sh` на чистом Debian 13 поднимает выбранные режимы без ручного редактирования конфигов
- [x] Ссылки в `/etc/xray-cli/client-links.txt` импортируются в v2rayN / Nekoray / Hiddify
- [x] `make lint && make test` проходят локально
- [x] README и docs/install.md описывают все режимы и флаги
