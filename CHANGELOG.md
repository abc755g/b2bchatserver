# Changelog

## [v1.2.0] — 18.09.2026

Тема релиза: федерация с партнёрскими серверами и подключение к внешним сервисам.

### Добавлено
- **MAS** (matrix-authentication-service `1.23.0`) в стек: опция `--mas`, для новых
  установок включена по умолчанию. База MAS создаётся в том же Postgres, конфиг
  генерирует сам MAS и правит `lib/mas-config.py`. С MAS работают Element X и
  вход через внешних OIDC-провайдеров; регистрация и пароли на стороне Synapse
  при этом выключаются.
- `manage.sh federation` без меню: `--list`, `--add`, `--remove`, `--mode`,
  `--sync-from <url>` (JSON-массив, `{"domains":[...]}` или построчно) и
  `--test <domain>` — проверка well-known, ключей сервера и собственной видимости.
- `manage.sh verify-domain --token [--path NAME]` — публикует токен подтверждения
  владения доменом по `/.well-known/NAME`. По умолчанию `b2b-matrix-verify` — путь,
  который проверяет B2B-портал; другому сервису имя задаётся через `--path`. Для
  этого well-known отдаётся файлами из `config/nginx/well-known/`, а не `return 200`
  в конфиге nginx.
- `manage.sh backup-key` — выгрузка ключа подписи отдельно от общего бэкапа;
  `start.sh` напоминает об этом сразу после установки.
- `manage.sh oidc --issuer --client-id [--name]` / `--disable` — внешний
  OIDC-провайдер для MAS; `manage.sh mas <...>` — прокладка к `mas-cli manage`;
  `manage.sh mas-migrate [--apply]` — `syn2mas` для существующих аккаунтов;
  `manage.sh admin-token` — токен для Admin UI (через MAS или паролем).
- Листенер федерации на `:8448` в nginx и compose — порт был открыт в ufw,
  но ничего на нём не слушало; работала только делегация через well-known.
- `.well-known/matrix/client` с MAS содержит `org.matrix.msc2965.authentication`,
  без этого Element X не находит, куда логиниться.
- Образ Synapse собирается всегда и включает `synapse-http-antispam==0.5.1` —
  модуль, который отдаёт решения о приглашениях, входе в комнаты и видимости в
  поиске внешнему HTTP-сервису. Без блока `modules:` в `homeserver.yaml` он
  ничего не делает; как включить — в `docs/external-integration.md`.
- Блок «Федерация» в `install.sh` отдельно предлагает сервер B2B-портала
  `chat.b2b-links.ru` (по умолчанию «да»; при перенастройке — как было раньше).
  Инсталлятор знает адреса портала, но ничего не подключает без согласия.
- Политика регистрации OAuth-клиентов MAS задаётся явно в `config.yaml`
  (`policy.data.client_registration`): только https и совпадение хоста
  `redirect_uri` с `client_uri`, контакт необязателен. Так внешние сервисы и
  Element X регистрируются сами, а обновление MAS не меняет правила молча.
- `health` показывает федерацию, MAS и готовность OAuth-входа для внешних
  сервисов (`auth_metadata` и регистрация клиентов), `info` — режим аутентификации.
- Документация: `docs/federation.md`, `docs/external-integration.md`.

### Изменено
- `manage.sh registration` и `password-reset` с MAS работают через него, а не
  через `homeserver.yaml` и `users.password_hash`.
- Бакет MinIO больше не получает анонимный доступ на скачивание: Synapse ходит с
  ключами, публичная политика раздавала бы вложения по прямой ссылке.
- Неудачный вход администратора на последнем шаге установки не роняет `start.sh`.
- `install.sh` ставит `python3`, если его нет.

### Исправлено
- В `homeserver.yaml` писалась опция `block_non_local_invites`, которой в Synapse
  нет: он молча игнорировал её, а администратор считал, что внешние приглашения
  заблокированы. Строка убрана; ограничение федерации обеспечивает whitelist.

## [v1.1.0] — 27.08.2026

### Изменено
- Все образы подняты до актуальных версий и вынесены в блок `IMG_*` в начале `start.sh` —
  теперь пин один на образ, а не разбросан по генератору `docker-compose.yml`:
  Synapse `v1.151.0` → `v1.159.0`, Element `v1.12.15` → `v1.12.26`,
  Cinny `v4.11.1` → `v4.12.6`, FluffyChat `v2.5.1` → `v2.9.1`,
  LiveKit `v1.11.0` → `v1.13.6`, lk-jwt-service `0.4.3` → `0.6.0`,
  PostgreSQL `16-alpine` → `16.15-alpine`.
- Запинены ранее плавающие теги: nginx `alpine` → `1.31.4-alpine`,
  coturn `alpine` → `4.17.2-alpine`, certbot `latest` → `v5.7.0`.
- Образ Synapse для режима S3 (`--minio`) больше не собирается от
  `matrixdotorg/synapse:latest` — используется тот же пин, что и в обычном режиме.
  `docker compose up` выполняется с `--build`, иначе смена пина не подхватывалась.

### Добавлено
- `LIVEKIT_FULL_ACCESS_HOMESERVERS` в сервис `livekit-jwt` — с версии `0.5.0`
  параметр обязателен, без него сервис не стартует.

### Исправлено
- Установка с `--minio` падала на сборке образа Synapse: в Dockerfile стоял
  несуществующий пакет `matrix-synapse-s3-storage-provider` (на PyPI такого нет).
  Правильное имя — `synapse-s3-storage-provider`, версия запинена (`1.7.0`).

## [v1.0.0] — первый релиз

### Добавлено
- Автоматическая установка Matrix (Synapse) сервера
- Поддержка клиентов: Element, Cinny, FluffyChat
- Интеграция B2B-связи
- SSL сертификаты через Let's Encrypt (автообновление)
- Звонки и видео (Coturn + LiveKit)
- Файловое хранилище (MinIO)
- Synapse Admin UI
- Автоматические бэкапы (локально и S3)
- Email уведомления (Yandex, Mail.ru, Gmail, кастомный SMTP)
- Интерактивный установщик (install.sh)
- Проверка целостности через SHA256SUMS
