# План реализации: импорт эталонного Xray Reality-клиента и паритетная настройка сервера

Branch: none (suggested: feature/xray-reality-reference-import; branch creation blocked because `.git` is read-only in the current environment)
Created: 2026-06-12

## Settings
- Testing: yes
- Logging: verbose
- Docs: yes

## Roadmap Linkage
Milestone: "none"
Rationale: ROADMAP.md отсутствует, связь с milestone пропущена.

## Обзор

Нужно доработать `xrayCli`, чтобы он умел брать рабочий клиентский Reality-конфиг как эталон, извлекать из него наблюдаемые параметры и настраивать наш сервер и клиентские артефакты максимально близко к этой схеме без ручной подгонки JSON.

### Что можно уверенно извлечь из эталонного клиента

- `protocol: vless`
- `security: reality`
- `network: tcp`
- `address: test.grey-lance.test-cdn-kkk.com`
- `port: 443`
- `id: c217c643-7791-4ea7-a8cf-55830d76a008`
- `flow: xtls-rprx-vision`
- `serverName: tradingview.com`
- `shortId: 50`
- `fingerprint: qq`
- `publicKey: -tePObR3oZwGAUOb5kqTYkNWl6rtUKl0RFuzuu06wgw`
- `remarks: Германия 🇩🇪`

### Что нельзя восстановить из клиентского JSON один в один

- Серверный `privateKey` Reality отсутствует в клиентском файле, поэтому точную копию исходного сервера собрать невозможно.
- `publicKey` из эталона можно использовать только для сравнения и диагностики; для нашего сервера `xrayCli` по умолчанию генерирует новую пару `x25519`, а в клиентскую ссылку и `client-reality.json` должен публиковаться уже новый сгенерированный `publicKey`.
- Поле `dest` на сервере в клиентском JSON не видно напрямую; его можно только вывести как безопасный дефолт из `serverName` и порта `443`, если пользователь не переопределил его явно.

### Текущие разрывы в `xrayCli`

- Reality-промпты и документация ограничены пресетами SNI и `fingerprint=chrome|random`, тогда как эталон использует `qq`.
- Генератор ссылок в [lib/link-builder.sh](/Users/k0rsair/ai/xrayCli/lib/link-builder.sh) всегда подставляет публичный IP, а не эталонный `address`/hostname.
- Конфигурация сервера в [lib/config-reality.sh](/Users/k0rsair/ai/xrayCli/lib/config-reality.sh) не умеет работать от импортированного клиентского шаблона и не фиксирует различие между “параметры можно повторить” и “параметры нужно регенерировать”.
- Нет тестов на парсинг эталонного Reality-конфига, на импорт `qq`, на `shortId=50` и на клиентский hostname вместо IP.

## Commit Plan

- **Commit 1** (after tasks 1-2): `feat: import reference reality client settings into installer state`
- **Commit 2** (after tasks 3-5): `feat: generate reality server and client artifacts from imported profile`
- **Commit 3** (after tasks 6-7): `test: cover reality profile import and document the new flow`

## Tasks

### Phase 1: Модель эталонного профиля и входные параметры

- [x] **Task 1: Добавить слой импорта эталонного Reality-клиента**
  - Создать модуль, например `lib/reality-reference.sh`, который через `jq` читает внешний JSON клиента и находит первый outbound `vless` + `security=reality`.
  - Извлекать и сохранять в runtime/state значения `REALITY_REFERENCE_ADDRESS`, `REALITY_REFERENCE_PORT`, `CLIENT_UUID`, `REALITY_SNI`, `REALITY_FLOW`, `REALITY_SHORT_ID`, `REALITY_FINGERPRINT`, `REALITY_REFERENCE_PUBLIC_KEY`, `REALITY_REMARKS`.
  - `REALITY_REFERENCE_PUBLIC_KEY` хранить именно как reference-значение для сравнения и операторской диагностики; оно не должно подменять рабочий `REALITY_PUBLIC_KEY`, который генерируется локально через `xray x25519`.
  - Явно помечать поля как `imported`, `derived`, `generated`, чтобы дальше не смешивать наблюдаемые значения клиента и серверные секреты.
  - **LOGGING REQUIREMENTS:** `DEBUG` на входе модуля с путём к JSON; `INFO` со списком извлечённых несекретных параметров; `WARN`, если JSON не содержит Reality outbound или если найдены только частичные данные; не логировать полный UUID и ключи без маскирования.
  - Файлы: `lib/reality-reference.sh`, правки `install.sh`, `lib/common.sh`

- [x] **Task 2: Расширить CLI-аргументы, state и интерактивные подсказки под импортированный профиль**
  - Добавить флаг вида `--reality-reference-json <path>` и опциональные overrides: `--reality-address`, `--client-uuid`, `--reality-short-id`, `--fingerprint`, `--reality-sni`, `--reality-dest`.
  - Обновить `install.sh`, `lib/prompts.sh`, `lib/crypto.sh`, чтобы импортированный профиль задавал дефолты, а пользователь мог их точечно переопределить, не ломая текущий цикл локальной генерации `REALITY_PRIVATE_KEY` и `REALITY_PUBLIC_KEY`.
  - Убрать искусственное ограничение на `fingerprint=chrome|random` в интерактивном и неинтерактивном сценариях; сохранить пресеты как удобный UI, но не как hard limit.
  - Persist-слой должен сохранять происхождение данных и итоговые значения в `state.env`, чтобы повторный `--reconfigure` не терял эталонные настройки.
  - **LOGGING REQUIREMENTS:** `DEBUG` для разбора аргументов и происхождения каждого параметра (`cli`, `reference`, `generated`, `default`); `INFO` для итогового Reality-профиля без секретов; `WARN` при конфликте override и импортированных данных.
  - Файлы: `install.sh`, `lib/prompts.sh`, `lib/crypto.sh`, `lib/common.sh`
  - Depends on: Task 1

### Phase 2: Паритетная генерация серверного Reality-конфига

- [x] **Task 3: Пересобрать Reality inbound вокруг импортированной модели и явных ограничений**
  - Обновить [lib/config-reality.sh](/Users/k0rsair/ai/xrayCli/lib/config-reality.sh) и [lib/config-merge.sh](/Users/k0rsair/ai/xrayCli/lib/config-merge.sh), чтобы `clients[].id`, `flow`, `serverNames`, `shortIds` и `dest` могли приходить из эталонного профиля или overrides.
  - Для `dest` использовать правило: явный `--reality-dest` > импортированное значение, если когда-нибудь появится в reference schema > производное `${REALITY_SNI}:443`.
  - Зафиксировать поведение для ключей: по умолчанию всегда генерировать новую пару `x25519` для нашего сервера; импортированный `REALITY_REFERENCE_PUBLIC_KEY` использовать только для сравнения/диагностики, а не как вход в server config. Если позже будет добавлен явный приватный ключ, он должен проходить отдельную валидацию, а не подменяться silently.
  - Сохранить совместимость с режимами `vless-reality` и `combo`, не ломая текущую схему внутренних портов.
  - **LOGGING REQUIREMENTS:** `DEBUG` при сборке inbound с маскированными секретами и финальным набором несекретных Reality-полей; `INFO` с итоговой схемой `dest/serverNames/shortIds`; `WARN`, если reference `publicKey` не совпадает с новым сгенерированным ключом клиента; `ERROR` при невалидном JSON или провале `xray -test`.
  - Файлы: `lib/config-reality.sh`, `lib/config-merge.sh`, `lib/crypto.sh`
  - Depends on: Task 2

- [x] **Task 4: Добавить паритетную генерацию клиентских артефактов, а не только `vless://` ссылки**
  - Обновить [lib/link-builder.sh](/Users/k0rsair/ai/xrayCli/lib/link-builder.sh), чтобы Reality-ссылка использовала явный `REALITY_ADDRESS`/hostname из эталона или override, а к public IP откатывалась только как fallback.
  - Добавить экспорт клиентского JSON-шаблона наподобие эталонного, например `/etc/xray-cli/client-reality.json`, с актуальными `address`, `port`, `id`, `flow`, `serverName`, `shortId`, `fingerprint`, `publicKey`, `remarks`, где `publicKey` всегда берётся из локально сгенерированного `REALITY_PUBLIC_KEY`, а не из импортированного эталона.
  - Сохранить текущий `client-links.txt`, чтобы не ломать существующий UX, но дополнять его указанием на JSON-артефакт.
  - **LOGGING REQUIREMENTS:** `DEBUG` при сборке link/json артефактов без вывода полного URI; `INFO` с путями к сохранённым файлам и типом адреса (`hostname`/`ip`); `WARN`, если импортированный hostname пуст и пришлось откатиться к IP.
  - Файлы: `lib/link-builder.sh`, `bin/xray-cli`, возможно `docs/install.md`
  - Depends on: Task 3

### Phase 3: Валидация, тесты и операторская наблюдаемость

- [x] **Task 5: Покрыть импорт эталонного профиля тестами и golden-сценариями**
  - Добавить unit/bats-тесты на разбор reference JSON, поддержку `fingerprint=qq`, перенос `shortId=50`, использование hostname вместо IP и предупреждение о невозможности восстановить `privateKey`.
  - Добавить golden-проверку Reality inbound и клиентского JSON-артефакта, чтобы фиксировать структуру после изменений.
  - Расширить fallback-тесты для сценариев без реального `xray` бинаря и без root.
  - **LOGGING REQUIREMENTS:** в тестах проверять наличие ожидаемых `WARN/INFO` сообщений на ветках import/fallback; не требовать production logging, но фиксировать семантику диагностических сообщений.
  - Файлы: `tests/bats/link_builder.bats`, новые `tests/bats/reality_reference.bats`, `tests/bats/fallback.sh`, при необходимости `Makefile`
  - Depends on: Task 4

- [x] **Task 6: Обновить summary/status, чтобы оператор видел, что именно было импортировано и что сгенерировано заново**
  - Расширить `bin/xray-cli status` и итоговый summary installer-а: показывать источник Reality-профиля, итоговый hostname/address, `serverName`, `fingerprint`, `shortId`, режим генерации ключей и наличие `client-reality.json`.
  - Сделать так, чтобы оператор сразу видел главный caveat: `reference publicKey` использован только как эталон для сверки, а сервер работает на новой или явной паре ключей, и в клиентские артефакты публикуется именно текущий сгенерированный `REALITY_PUBLIC_KEY`.
  - **LOGGING REQUIREMENTS:** `INFO` при печати summary/status; `DEBUG` при чтении state и определении происхождения параметров; `WARN`, если state неполный и status не может честно показать источник настройки.
  - Файлы: `bin/xray-cli`, `lib/service.sh`, `lib/crypto.sh`
  - Depends on: Task 4

### Phase 4: Документация и безопасный операторский сценарий

- [x] **Task 7: Обновить README и install docs под сценарий reverse engineering from client config**
  - Добавить documented flow: “есть стабильный клиентский JSON → импортируем эталон → поднимаем свой Reality server → получаем новый client link/json”.
  - Отдельно описать невосстанавливаемые поля (`privateKey`), правило вывода `dest` из `serverName`, поддержку кастомных fingerprints вроде `qq`, и разницу между эталонным `publicKey` и новым серверным ключом.
  - Обновить troubleshooting для случаев, когда импортированный клиентский JSON неполный или когда после импорта оператор ожидает точную копию удалённого сервера.
  - **LOGGING REQUIREMENTS:** n/a для документации, но примеры команд и ожидаемые summary/warn сообщения должны совпадать с реальным CLI.
  - Файлы: `README.md`, `docs/install.md`
  - Depends on: Task 5, Task 6

## Риски и митигация

| Риск | Митигация |
|------|-----------|
| Пользователь ожидает точную копию удалённого сервера по одному клиентскому JSON | Явный `WARN` и документация: без `privateKey` возможна только паритетная, а не идентичная конфигурация |
| Импортированный `address` — hostname, а текущий код жёстко подставляет IP | Ввести отдельное поле адреса Reality и использовать IP только как fallback |
| Кастомные fingerprints (`qq`) ломаются из-за старых UI-ограничений | Снять hardcoded whitelist, покрыть тестом и документацией |
| Повторный `--reconfigure` теряет reference-параметры | Persist источника и итоговых значений в `state.env` |
| Смешение reference `publicKey` и нового серверного keypair вводит в заблуждение | Показывать источник ключа в summary/status и писать ссылку и `client-reality.json` только с текущим локально сгенерированным `REALITY_PUBLIC_KEY` |

## Definition of Done

- [ ] Установщик принимает эталонный клиентский Reality JSON и извлекает из него пригодные параметры без ручного редактирования кода
- [ ] Server config и клиентские артефакты используют imported/override поля предсказуемо и прозрачно
- [ ] `vless://` ссылка и `client-reality.json` отражают новый серверный `publicKey`, но сохраняют эталонные `address/serverName/shortId/fingerprint`, когда это допустимо
- [ ] `make test` покрывает import flow, `qq`, hostname address и диагностические предупреждения
- [ ] README и `docs/install.md` честно описывают границы reverse engineering по клиентскому JSON
