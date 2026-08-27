# Changelog

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
