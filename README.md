# B2B-чат

Самостоятельно размещаемый корпоративный мессенджер на базе Matrix/Synapse.  
Развёртывается одной командой, управляется через простой интерфейс.

## Регистрация VDS (ссылки)

Сервис можно развернуть на вашем собственном сервере или на VDS.

Домен для установки обязателен (например, `chat.yourcompany.ru`): без домена не получится корректно настроить SSL и доступ к серверу.

Если выбираете VDS и регистраторов доменов, мы рекомендуем проверенные компании с оптимальным соотношением "цена-качество":

- firstVDS: [https://firstvds.ru/?from=519065](https://firstvds.ru/?from=519065) (промокод `648519065` для скидки 25% на первый месяц)
- Timeweb Cloud: [https://timeweb.cloud/?i=141497](https://timeweb.cloud/?i=141497)
- Selectel: [https://selectel.ru/?ref_code=beeabc92bf](https://selectel.ru/?ref_code=beeabc92bf)

Подробные пошаговые инструкции для каждого провайдера:

- [firstVDS](docs/providers/firstvds.md)
- [Timeweb Cloud](docs/providers/timeweb.md)
- [Selectel](docs/providers/selectel.md)

## Что внутри

| Компонент     | Назначение                              | Версия образа              |
|---------------|-----------------------------------------|----------------------------|
| Synapse       | Matrix-сервер (+ модуль политик `synapse-http-antispam`) | `v1.159.0` |
| MAS           | Сервис аутентификации (Element X, SSO)  | `1.23.0`                   |
| Element       | Веб-клиент (опционально)                | `v1.12.26`                 |
| Cinny         | Альтернативный веб-клиент (опционально) | `v4.12.6`                  |
| FluffyChat    | Ещё один веб-клиент (опционально)       | `v2.9.1`                   |
| PostgreSQL    | База данных                             | `16.15-alpine`             |
| nginx         | Обратный прокси + SSL                   | `1.31.4-alpine`            |
| Let's Encrypt | Автоматические SSL-сертификаты          | `certbot v5.7.0`           |
| MinIO         | S3-хранилище медиафайлов (опционально)  | `RELEASE.2025-09-07`       |
| Coturn        | STUN/TURN сервер для звонков            | `4.17.2-alpine`            |
| LiveKit       | SFU для групповых видеозвонков          | `v1.13.6`                  |
| livekit-jwt   | JWT-сервис для интеграции звонков       | `0.6.0`                    |
| Synapse Admin | Панель администратора                   | `0.11.4`                   |

Все версии запинены в блоке `IMG_*` в начале `start.sh`. `manage.sh update` подтягивает
пересобранные образы тех же тегов; смена версии — правка пина и повторный запуск `start.sh`.

## Требования

| Пользователей | CPU | RAM   | Диск    |
|---------------|-----|-------|---------|
| до 50         | 2   | 2 GB  | 20 GB   |
| до 200        | 2   | 4 GB  | 50 GB   |
| до 500        | 4   | 8 GB  | 100 GB  |
| более 500     | 4+  | 16 GB | 200 GB+ |

Со звонками: +1 CPU, +2 GB RAM.

**OS:** Ubuntu 20.04 / 22.04 LTS

**Открытые порты:** 80, 443, 8448  
**Со звонками:** дополнительно 3478 UDP/TCP, 49152–49200 UDP

> Если сервер находится в облаке (Timeweb, VK Cloud и др.) — откройте порты также в панели провайдера (Firewall / Security Groups).
> Порт `8448` зарезервирован под Matrix Federation: не используйте его для `--port`, `--admin-port`, `--cinny-port`, `--fluffychat-port` или `--minio-port`.

## Установка

```bash
curl -fsSL https://github.com/abc755g/b2bchatserver/releases/latest/download/install.sh -o /tmp/b2b-install.sh && sudo bash /tmp/b2b-install.sh
```

Скрипт задаст вопросы о домене, паролях, компонентах и запустит всё автоматически.

### Предварительно

Перед запуском установки создайте **A-запись** в DNS вашего домена:

| Параметр | Значение                            |
|----------|-------------------------------------|
| Тип      | A                                   |
| Имя      | Ваш домен (напр. matrix.company.ru) |
| Адрес    | IP вашего сервера                   |
| TTL      | 300                                 |

После добавления подождите 5–30 минут.

## Первый вход

1. Откройте браузер: `https://ВАШ_ДОМЕН`
2. Войдите под логином `@admin:ВАШ_ДОМЕН`
3. Для создания аккаунтов сотрудников откройте Admin UI (адрес показывается по окончании установки)

**Мобильное приложение:**
- iOS: App Store → **Element**
- Android: Google Play → **Element**
- При входе укажите сервер: `https://ВАШ_ДОМЕН`

## Другие клиенты Matrix

Помимо Element можно использовать и другие клиенты (web и мобильные):

**Web-клиенты:**
- **Cinny** — лёгкий и быстрый web-клиент (можно установить через `install.sh`)
- **FluffyChat Web** — web-версия FluffyChat (можно установить через `install.sh`)

**Мобильные клиенты:**
- **FluffyChat** (iOS/Android)
- **Element X** (iOS/Android, новое поколение клиента от Element)

При использовании любого клиента указывайте homeserver:
- `https://ВАШ_ДОМЕН`

> Важно: поддержка некоторых функций (например, звонков и новых experimental-фич) может отличаться между клиентами.

## Управление

Все команды запускаются из директории `/opt/b2b-chat`:

```bash
./manage.sh start              # Запустить стек
./manage.sh stop               # Остановить (данные не удаляются)
./manage.sh restart            # Перезапустить
./manage.sh status             # Статус контейнеров
./manage.sh health             # Проверка работоспособности
./manage.sh logs               # Логи всех сервисов
./manage.sh logs --service X   # Логи конкретного сервиса
./manage.sh update             # Обновить образы Docker
./manage.sh backup             # Запустить бэкап прямо сейчас
./manage.sh registration       # Включить/выключить регистрацию
./manage.sh federation         # Управление федерацией (см. ниже)
./manage.sh verify-domain --token T   # Опубликовать токен подтверждения домена
./manage.sh backup-key         # Сохранить ключ подписи сервера
./manage.sh admin-token        # Токен администратора для Admin UI
./manage.sh oidc ...           # Вход через внешнего OIDC-провайдера (нужен MAS)
./manage.sh mas ...            # Прямой вызов mas-cli manage
./manage.sh mas-migrate        # Перенос аккаунтов Synapse → MAS
./manage.sh password-reset     # Сбросить пароль пользователя
./manage.sh ssl-renew          # Принудительно обновить SSL
./manage.sh media-clean        # Очистить кэш медиафайлов
./manage.sh wipe               # Полная очистка (удаляет данные и конфиги)
./manage.sh info               # Адреса, статус, порты
```

Для изменения настроек (компоненты, домен, SMTP и др.):

```bash
./install.sh
```

## Бэкапы

Настраиваются при установке. Доступные варианты:
- **Локально** на сервере (указывается папка и срок хранения)
- **S3-хранилище** (Yandex Object Storage, любое S3-совместимое)
- **Оба варианта** одновременно

Запуск бэкапа вручную:
```bash
./manage.sh backup
```

> Signing key (`config/synapse/*.signing.key`) — единственный файл, который нельзя
> восстановить. При его потере другие серверы перестанут доверять вашему, и починить
> это можно только сменой домена. Сохраните его отдельно сразу после установки:
> `./manage.sh backup-key --out ~/matrix-signing-key`, затем унесите с сервера.

## Аутентификация (MAS)

Начиная с v1.2.0 в стек входит MAS — matrix-authentication-service. Он нужен для
мобильного Element X и для входа через внешних провайдеров (SSO). Включён по
умолчанию для новых установок; на существующем сервере включается через
`./install.sh` → «изменить настройки», после чего аккаунты переносятся:

```bash
./manage.sh mas-migrate          # проверка, ничего не меняет
./manage.sh mas-migrate --apply  # перенос; Synapse на это время останавливается
```

С MAS пароли и регистрация живут в нём, а не в Synapse:
`./manage.sh password-reset` и `./manage.sh registration` это учитывают,
токен для Admin UI выдаёт `./manage.sh admin-token`.

Вход через внешнего OIDC-провайдера (корпоративный SSO, внешний портал):

```bash
./manage.sh oidc --issuer https://id.company.ru --client-id <ID> --name "Компания"
```

Команда печатает `redirect_uri`, который нужно зарегистрировать у провайдера.
Локальный вход по паролю при этом остаётся — на случай недоступности провайдера.

## Федерация

Matrix позволяет общаться с пользователями других серверов. Режимы:
- **Whitelist** — только указанные серверы (по умолчанию; напр. серверы партнёров)
- **Закрытая** — изолированный контур, только внутренние пользователи
- **Открытая** — общение со всем Matrix-миром (включая matrix.org)

```bash
./manage.sh federation                        # меню
./manage.sh federation --list                 # режим и список
./manage.sh federation --add chat.partner.ru  # добавить сервер
./manage.sh federation --remove chat.partner.ru
./manage.sh federation --sync-from https://.../servers.json   # список по URL
./manage.sh federation --mode open|closed|whitelist
./manage.sh federation --test chat.partner.ru # проверить связность в обе стороны
```

Список читается Synapse только при старте, поэтому каждая команда перезапускает
его сама. Подробно — [docs/federation.md](docs/federation.md); подключение к
внешнему порталу или сервису — [docs/external-integration.md](docs/external-integration.md).

## Лицензия

Apache License 2.0 — см. [LICENSE](LICENSE)
