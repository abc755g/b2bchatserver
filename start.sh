#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${BLUE}[..]${NC} $*"; }
warn() { echo -e "${YELLOW}[!!]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

# ── Справка ───────────────────────────────────────────────
usage() {
    echo ""
    echo "Использование:"
    echo "  ./start.sh --domain DOMAIN --email EMAIL --admin-user USER [опции]"
    echo ""
    echo "Обязательные:"
    echo "  --domain         Домен Synapse сервера       (matrix.company.ru)"
    echo "  --email          Email для Let's Encrypt     (admin@company.ru)"
    echo "  --admin-user     Логин администратора         (admin)"
    echo ""
    echo "Опциональные:"
    echo "  --server-name    Домен пользователей Matrix  (company.ru)"
    echo "                   по умолчанию = --domain"
    echo "  --client         Клиент (можно несколько раз) (element|cinny|fluffychat)"
    echo "                   по умолчанию = element"
    echo "  --port           Порт HTTPS основного домена (по умолчанию: 443)"
    echo "  --minio          Включить MinIO для S3-медиа"
    echo "  --minio-port     Порт MinIO Console          (по умолчанию: случайный)"
    echo "  --admin-port     Порт Synapse Admin          (по умолчанию: случайный)"
    echo "  --cinny-port     Порт Cinny                  (по умолчанию: случайный)"
    echo "  --fluffychat-port Порт FluffyChat            (по умолчанию: случайный)"
    echo "  --calls          Включить звонки (Coturn + LiveKit)"
    echo "  --open-registration  Открытая регистрация пользователей"
    echo "  --max-upload     Макс. размер файла          (по умолчанию: 500M)"
    echo ""
    echo "SMTP:"
    echo "  --smtp-host      SMTP сервер                 (smtp.yandex.ru)"
    echo "  --smtp-port      SMTP порт                   (465)"
    echo "  --smtp-user      SMTP логин"
    echo "  --smtp-from      Email отправителя"
    echo ""
    echo "Бэкапы:"
    echo "  --backup-local PATH   Папка для локальных бэкапов"
    echo "  --backup-days N       Хранить локально (дней, по умолчанию: 30)"
    echo "  --backup-s3           Включить S3 бэкапы"
    echo "  --s3-endpoint URL     S3 endpoint"
    echo "  --s3-bucket NAME      S3 bucket"
    echo "  --s3-days N           Хранить в S3 (дней, по умолчанию: 90)"
    echo "  --backup-media        Включить бэкап медиафайлов"
    echo "  --backup-schedule N   1=ежедневно 3:00, 2=каждые 12ч"
    echo "  --env-file PATH       Файл переменных окружения для секретов"
    echo "  --allow-direct-run    Подтвердить прямой запуск start.sh"
    echo ""
    echo "Секреты (только через --env-file):"
    echo "  ADMIN_PASS, DB_PASS, MINIO_PASS, SMTP_PASS,"
    echo "  S3_ACCESS_KEY, S3_SECRET_KEY, TURN_SECRET,"
    echo "  LIVEKIT_KEY, LIVEKIT_SECRET"
    echo ""
    echo "  --help           Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  # Только Element"
    echo "  ./start.sh --domain matrix.company.ru --email admin@company.ru \\"
    echo "             --admin-user admin --env-file ./.secrets.env"
    echo ""
    echo "  # Все клиенты + звонки"
    echo "  ./start.sh --domain matrix.company.ru --server-name company.ru \\"
    echo "             --email admin@company.ru \\"
    echo "             --admin-user admin --env-file ./.secrets.env \\"
    echo "             --client element --client cinny --client fluffychat \\"
    echo "             --calls"
    echo ""
}

# ── Парсинг аргументов ────────────────────────────────────
DOMAIN=""
SERVER_NAME=""
EMAIL=""
ADMIN_USER=""
ADMIN_PASS=""
CLIENTS=""
PORT="443"
MINIO_PORT=""
ADMIN_PORT=""
CINNY_PORT=""
FLUFFYCHAT_PORT=""
DB_PASS=""
MINIO_PASS=""
USE_CALLS=false
USE_MINIO=false
OPEN_REGISTRATION=false
MAX_UPLOAD="500M"
FEDERATION_MODE="whitelist"
FEDERATION_SERVERS=""

SMTP_HOST=""
SMTP_PORT=""
SMTP_USER=""
SMTP_PASS=""
SMTP_FROM=""

BACKUP_LOCAL=""
BACKUP_DAYS="30"
BACKUP_S3=false
S3_ENDPOINT=""
S3_BUCKET=""
S3_ACCESS_KEY=""
S3_SECRET_KEY=""
S3_DAYS="90"
BACKUP_MEDIA=false
BACKUP_SCHEDULE="1"
REINSTALL=false
ENV_FILE=""
ALLOW_DIRECT_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)           DOMAIN="$2";           shift 2 ;;
        --server-name)      SERVER_NAME="$2";      shift 2 ;;
        --email)            EMAIL="$2";            shift 2 ;;
        --admin-user)       ADMIN_USER="$2";       shift 2 ;;
        --admin-pass)       err "Передача секретов через CLI запрещена. Используйте --env-file (ADMIN_PASS)." ;;
        --client)           CLIENTS="${CLIENTS},$2"; shift 2 ;;
        --port)             PORT="$2";             shift 2 ;;
        --minio-port)       MINIO_PORT="$2";       shift 2 ;;
        --admin-port)       ADMIN_PORT="$2";       shift 2 ;;
        --cinny-port)       CINNY_PORT="$2";       shift 2 ;;
        --fluffychat-port)  FLUFFYCHAT_PORT="$2";  shift 2 ;;
        --db-pass)          err "Передача секретов через CLI запрещена. Используйте --env-file (DB_PASS)." ;;
        --minio-pass)       err "Передача секретов через CLI запрещена. Используйте --env-file (MINIO_PASS)." ;;
        --calls)            USE_CALLS=true;        shift ;;
        --minio)            USE_MINIO=true;        shift ;;
        --open-registration) OPEN_REGISTRATION=true; shift ;;
        --max-upload)       MAX_UPLOAD="$2";       shift 2 ;;
        --federation-mode)    FEDERATION_MODE="$2";    shift 2 ;;
        --federation-servers) FEDERATION_SERVERS="$2"; shift 2 ;;
        --smtp-host)        SMTP_HOST="$2";        shift 2 ;;
        --smtp-port)        SMTP_PORT="$2";        shift 2 ;;
        --smtp-user)        SMTP_USER="$2";        shift 2 ;;
        --smtp-pass)        err "Передача секретов через CLI запрещена. Используйте --env-file (SMTP_PASS)." ;;
        --smtp-from)        SMTP_FROM="$2";        shift 2 ;;
        --backup-local)     BACKUP_LOCAL="$2";     shift 2 ;;
        --backup-days)      BACKUP_DAYS="$2";      shift 2 ;;
        --backup-s3)        BACKUP_S3=true;        shift ;;
        --s3-endpoint)      S3_ENDPOINT="$2";      shift 2 ;;
        --s3-bucket)        S3_BUCKET="$2";        shift 2 ;;
        --s3-access-key)    err "Передача секретов через CLI запрещена. Используйте --env-file (S3_ACCESS_KEY)." ;;
        --s3-secret-key)    err "Передача секретов через CLI запрещена. Используйте --env-file (S3_SECRET_KEY)." ;;
        --s3-days)          S3_DAYS="$2";          shift 2 ;;
        --backup-media)     BACKUP_MEDIA=true;     shift ;;
        --backup-schedule)  BACKUP_SCHEDULE="$2";  shift 2 ;;
        --env-file)         ENV_FILE="$2";         shift 2 ;;
        --allow-direct-run) ALLOW_DIRECT_RUN=true; shift ;;
        --reinstall)        REINSTALL=true;        shift ;;
        --help|-h)          usage; exit 0 ;;
        *) err "Неизвестный параметр: $1. Используйте --help." ;;
    esac
done

# ── Загрузка секретов из env-file (если указан) ───────────
if [ -n "$ENV_FILE" ]; then
    [ ! -f "$ENV_FILE" ] && err "Файл переменных не найден: $ENV_FILE"
    while IFS='=' read -r key value; do
        key="${key%%[[:space:]]*}"
        [ -z "$key" ] && continue
        [[ "$key" =~ ^# ]] && continue
        case "$key" in
            ADMIN_PASS|DB_PASS|MINIO_PASS|SMTP_PASS|S3_ACCESS_KEY|S3_SECRET_KEY|TURN_SECRET|LIVEKIT_KEY|LIVEKIT_SECRET)
                [ -z "${!key:-}" ] && printf -v "$key" '%s' "$value"
                ;;
        esac
    done < "$ENV_FILE"
fi

# ── Прямой запуск start.sh не рекомендуется ───────────────
if [ "${INSTALL_FROM_INSTALL_SH:-false}" != "true" ] && [ "$ALLOW_DIRECT_RUN" != "true" ]; then
    warn "Рекомендуемый способ установки: ./install.sh"
    warn "Прямой запуск start.sh может быть небезопасен и не поддерживается как основной сценарий."
    read -rp "$(echo -e "${YELLOW}?${NC} Продолжить прямой запуск? [y/N]: ")" _DIRECT_CONFIRM
    _DIRECT_CONFIRM="${_DIRECT_CONFIRM:-n}"
    [[ "$_DIRECT_CONFIRM" =~ ^[Yy]$ ]] || err "Запуск отменён. Используйте ./install.sh"
fi

# ── Fallback: пароль администратора для первой установки ──
if [ -z "$ADMIN_PASS" ] && [ ! -f ".env" ]; then
    warn "Пароль администратора не передан — запрашиваем интерактивно."
    while true; do
        read -rsp "$(echo -e "${BLUE}?${NC} Укажите пароль администратора: ")" ADMIN_PASS
        echo ""
        if [ ${#ADMIN_PASS} -lt 8 ]; then
            warn "Минимум 8 символов"
            continue
        fi
        read -rsp "$(echo -e "${BLUE}?${NC} Укажите пароль повторно: ")" ADMIN_PASS2
        echo ""
        if [ "$ADMIN_PASS" = "$ADMIN_PASS2" ]; then
            break
        else
            warn "Пароли не совпадают"
        fi
    done
fi

# ── Проверка обязательных ─────────────────────────────────
MISSING=""
[ -z "$DOMAIN" ]     && MISSING="${MISSING}\n  --domain"
[ -z "$EMAIL" ]      && MISSING="${MISSING}\n  --email"
[ -z "$ADMIN_USER" ] && MISSING="${MISSING}\n  --admin-user"
# ADMIN_PASS обязателен для первой установки (через --env-file или интерактивный ввод)
[ -z "$ADMIN_PASS" ] && [ ! -f ".env" ] && MISSING="${MISSING}\n  ADMIN_PASS (через --env-file)"

if [ -n "$MISSING" ]; then
    echo -e "${RED}[ERR]${NC} Не указаны обязательные параметры:${MISSING}"
    usage; exit 1
fi

# ── Определяем режим установки ───────────────────────────
# install   — первая установка (нет .env)
# modify    — изменить настройки, данные сохранить
# reinstall — полная переустановка, данные удалить (флаг --reinstall)
INSTALL_MODE="install"
[ -f ".env" ]   && INSTALL_MODE="modify"
$REINSTALL      && INSTALL_MODE="reinstall"

# ── Дефолты ───────────────────────────────────────────────
[ -z "$SERVER_NAME" ] && SERVER_NAME="${DOMAIN}"

# Рандомные порты для скрытых сервисов (20000–60000)
rand_port() { shuf -i 20000-60000 -n 1; }

is_valid_port() {
    local _p="$1"
    [[ "$_p" =~ ^[0-9]+$ ]] && [ "$_p" -ge 1 ] && [ "$_p" -le 65535 ]
}

ensure_unique_port() {
    local _name="$1" _port="$2"
    shift 2
    local _existing
    for _existing in "$@"; do
        [ -z "$_existing" ] && continue
        if [ "$_port" = "$_existing" ]; then
            err "Конфликт портов: ${_name} использует порт ${_port}, который уже занят другим сервисом."
        fi
    done
    return 0
}

next_unique_random_port() {
    local _candidate
    while true; do
        _candidate=$(rand_port)
        local _conflict=false
        local _existing
        for _existing in "$@"; do
            [ "$_candidate" = "$_existing" ] && _conflict=true && break
        done
        if [ "$_conflict" = "false" ]; then
            echo "$_candidate"
            return
        fi
    done
}

is_valid_port "$PORT" || err "Некорректный порт Element/Synapse: ${PORT} (допустимо: 1-65535)"
[ "$PORT" = "80" ] && err "Порт Element/Synapse не может быть 80: этот порт зарезервирован под HTTP-челленджи Let's Encrypt."
[ "$PORT" = "8448" ] && err "Порт Element/Synapse не может быть 8448: этот порт зарезервирован под Matrix Federation."

[ -n "$MINIO_PORT" ]      && is_valid_port "$MINIO_PORT"      || [ -z "$MINIO_PORT" ]      || err "Некорректный порт MinIO: ${MINIO_PORT}"
[ -n "$ADMIN_PORT" ]      && is_valid_port "$ADMIN_PORT"      || [ -z "$ADMIN_PORT" ]      || err "Некорректный порт Admin UI: ${ADMIN_PORT}"
[ -n "$CINNY_PORT" ]      && is_valid_port "$CINNY_PORT"      || [ -z "$CINNY_PORT" ]      || err "Некорректный порт Cinny: ${CINNY_PORT}"
[ -n "$FLUFFYCHAT_PORT" ] && is_valid_port "$FLUFFYCHAT_PORT" || [ -z "$FLUFFYCHAT_PORT" ] || err "Некорректный порт FluffyChat: ${FLUFFYCHAT_PORT}"

# Сначала проверяем пользовательские порты на дубли, затем генерируем отсутствующие.
# 80 зарезервирован под HTTP-челленджи, 443 занят основным HTTPS server-блоком nginx,
# 8448 зарезервирован под Matrix Federation.
[ -n "$MINIO_PORT" ]      && ensure_unique_port "MinIO" "$MINIO_PORT" "$PORT" "80" "443" "8448"
[ -n "$ADMIN_PORT" ]      && ensure_unique_port "Admin UI" "$ADMIN_PORT" "$PORT" "80" "443" "8448" "$MINIO_PORT"
[ -n "$CINNY_PORT" ]      && ensure_unique_port "Cinny" "$CINNY_PORT" "$PORT" "80" "443" "8448" "$MINIO_PORT" "$ADMIN_PORT"
[ -n "$FLUFFYCHAT_PORT" ] && ensure_unique_port "FluffyChat" "$FLUFFYCHAT_PORT" "$PORT" "80" "443" "8448" "$MINIO_PORT" "$ADMIN_PORT" "$CINNY_PORT"

$USE_MINIO && [ -z "$MINIO_PORT" ] && MINIO_PORT=$(next_unique_random_port "$PORT" "80" "443" "8448")
[ -z "$ADMIN_PORT" ]      && ADMIN_PORT=$(next_unique_random_port "$PORT" "80" "443" "8448" "$MINIO_PORT")
[ -z "$CINNY_PORT" ]      && CINNY_PORT=$(next_unique_random_port "$PORT" "80" "443" "8448" "$MINIO_PORT" "$ADMIN_PORT")
[ -z "$FLUFFYCHAT_PORT" ] && FLUFFYCHAT_PORT=$(next_unique_random_port "$PORT" "80" "443" "8448" "$MINIO_PORT" "$ADMIN_PORT" "$CINNY_PORT")

# Финальная проверка (включая случайно сгенерированные значения)
ensure_unique_port "MinIO" "$MINIO_PORT" "$PORT" "80" "443" "8448"
ensure_unique_port "Admin UI" "$ADMIN_PORT" "$PORT" "80" "443" "8448" "$MINIO_PORT"
ensure_unique_port "Cinny" "$CINNY_PORT" "$PORT" "80" "443" "8448" "$MINIO_PORT" "$ADMIN_PORT"
ensure_unique_port "FluffyChat" "$FLUFFYCHAT_PORT" "$PORT" "80" "443" "8448" "$MINIO_PORT" "$ADMIN_PORT" "$CINNY_PORT"
[ -z "$SMTP_FROM" ] && SMTP_FROM="${SMTP_USER}"

SMTP_ENABLED=false
[ -n "$SMTP_HOST" ] && [ -n "$SMTP_USER" ] && SMTP_ENABLED=true

BACKUP_ENABLED=false
[ -n "$BACKUP_LOCAL" ] && BACKUP_ENABLED=true
$BACKUP_S3 && BACKUP_ENABLED=true

# ── Определяем какие клиенты включены ────────────────────
USE_ELEMENT=false
USE_CINNY=false
USE_FLUFFYCHAT=false

CLIENTS="${CLIENTS#,}"  # убираем ведущую запятую
IFS=',' read -ra CLIENT_LIST <<< "$CLIENTS"
for c in "${CLIENT_LIST[@]}"; do
    c=$(echo "$c" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    case "$c" in
        element)    USE_ELEMENT=true ;;
        cinny)      USE_CINNY=true ;;
        fluffychat) USE_FLUFFYCHAT=true ;;
        *) [ -n "$c" ] && warn "Неизвестный клиент: $c (доступные: element, cinny, fluffychat)" ;;
    esac
done

# Если ни один не выбран — включаем element
if ! $USE_ELEMENT && ! $USE_CINNY && ! $USE_FLUFFYCHAT; then
    warn "Клиент не указан — включаем Element по умолчанию"
    USE_ELEMENT=true
fi

# ── Пароли ────────────────────────────────────────────────
# В режиме modify — читаем существующие пароли из .env
if [ "$INSTALL_MODE" = "modify" ] && [ -f ".env" ]; then
    info "Читаем существующие пароли из .env..."
    _EDBP=$(grep "^POSTGRES_PASSWORD=" .env | cut -d= -f2)
    _EMIP=$(grep "^MINIO_ROOT_PASSWORD=" .env | cut -d= -f2)
    _ETSEC=$(grep "^TURN_SECRET=" .env | cut -d= -f2)
    _ELVK=$(grep "^LIVEKIT_API_KEY=" .env | cut -d= -f2)
    _ELVS=$(grep "^LIVEKIT_API_SECRET=" .env | cut -d= -f2)
    [ -n "$_EDBP" ]  && DB_PASS="$_EDBP"
    [ -n "$_EMIP" ]  && MINIO_PASS="$_EMIP"
    [ -n "$_ETSEC" ] && TURN_SECRET="$_ETSEC"
    [ -n "$_ELVK" ]  && LIVEKIT_KEY="$_ELVK"
    [ -n "$_ELVS" ]  && LIVEKIT_SECRET="$_ELVS"
    log "Существующие пароли сохранены"
fi

[ -z "$DB_PASS" ]    && DB_PASS=$(openssl rand -hex 16)
[ -z "$MINIO_PASS" ] && MINIO_PASS=$(openssl rand -hex 16)

# Сохраняем REG_SECRET в modify-режиме — иначе старые токены перестанут работать
if [ "$INSTALL_MODE" = "modify" ] && [ -f ".env" ]; then
    _EXISTING_REG=$(grep "^REGISTRATION_SHARED_SECRET=" .env | cut -d= -f2)
    REG_SECRET="${_EXISTING_REG:-$(openssl rand -hex 32)}"
else
    REG_SECRET=$(openssl rand -hex 32)
fi

if $USE_CALLS; then
    [ -z "$TURN_SECRET" ]    && TURN_SECRET=$(openssl rand -hex 32)
    [ -z "$LIVEKIT_KEY" ]    && LIVEKIT_KEY=$(openssl rand -hex 8)
    [ -z "$LIVEKIT_SECRET" ] && LIVEKIT_SECRET=$(openssl rand -hex 32)
fi

# ── Сводка ────────────────────────────────────────────────
CLIENTS_DISPLAY=""
$USE_ELEMENT    && CLIENTS_DISPLAY="${CLIENTS_DISPLAY}element,"
$USE_CINNY      && CLIENTS_DISPLAY="${CLIENTS_DISPLAY}cinny,"
$USE_FLUFFYCHAT && CLIENTS_DISPLAY="${CLIENTS_DISPLAY}fluffychat,"
CLIENTS_DISPLAY="${CLIENTS_DISPLAY%,}"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                 B2B-чат — запуск                        ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  Synapse:  %-46s ║\n" "${DOMAIN}"
printf "║  Домен:    %-46s ║\n" "${SERVER_NAME}"
printf "║  Клиенты:  %-46s ║\n" "${CLIENTS_DISPLAY:-element}"
$USE_CALLS && printf "║  Звонки:   %-46s ║\n" "включены (Coturn + LiveKit)"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Docker ────────────────────────────────────────────────
info "Проверяем Docker..."
if ! command -v docker &>/dev/null; then
    warn "Docker не найден — устанавливаем..."
    apt-get update --allow-releaseinfo-change -y 2>/dev/null || true
    curl -fsSL https://get.docker.com | sh
    apt-get install -y docker-compose-plugin 2>/dev/null || true
    systemctl enable --now docker 2>/dev/null || true
    log "Docker установлен"
else
    log "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
fi
log "docker compose: $(docker compose version --short)"

# ── Переустановка: сносим всё ────────────────────────────
if [ "$INSTALL_MODE" = "reinstall" ]; then
    info "Останавливаем и удаляем все контейнеры и данные..."
    docker compose down -v 2>/dev/null || true
    log "Данные удалены — начинаем чистую установку"
fi

# ── Firewall (ufw) ────────────────────────────────────────
info "Настраиваем firewall..."
if ! command -v ufw &>/dev/null; then
    apt-get install -y ufw 2>/dev/null && log "ufw установлен" || warn "Не удалось установить ufw"
fi

if command -v ufw &>/dev/null; then
    ufw allow 22/tcp              comment "SSH"               2>/dev/null || true
    ufw allow 80/tcp              comment "HTTP Let's Encrypt" 2>/dev/null || true
    ufw allow ${PORT}/tcp         comment "HTTPS Element"     2>/dev/null || true
    $USE_MINIO && ufw allow ${MINIO_PORT}/tcp comment "HTTPS MinIO" 2>/dev/null || true
    ufw allow ${ADMIN_PORT}/tcp   comment "HTTPS Admin"       2>/dev/null || true
    $USE_CINNY      && ufw allow ${CINNY_PORT}/tcp      comment "HTTPS Cinny"      2>/dev/null || true
    $USE_FLUFFYCHAT && ufw allow ${FLUFFYCHAT_PORT}/tcp  comment "HTTPS FluffyChat" 2>/dev/null || true
    ufw allow 8448/tcp            comment "Matrix Federation"  2>/dev/null || true
    if $USE_CALLS; then
        ufw allow 3478/tcp          comment "TURN TCP"           2>/dev/null || true
        ufw allow 3478/udp          comment "STUN/TURN UDP"      2>/dev/null || true
        ufw allow 49152:49200/udp   comment "TURN media"         2>/dev/null || true
        ufw allow 7881/tcp          comment "LiveKit RTC TCP"    2>/dev/null || true
        ufw allow 50000:50010/udp   comment "LiveKit media UDP"  2>/dev/null || true
    fi
    ufw --force enable 2>/dev/null || true
    ufw reload 2>/dev/null || true
    log "Firewall настроен"
fi

# ── Проверка DNS ──────────────────────────────────────────
info "Проверяем DNS..."
SERVER_IP=$(curl -sf --max-time 5 https://api.ipify.org || \
            curl -sf --max-time 5 https://ifconfig.me || \
            hostname -I | awk '{print $1}')

DNS_OK=true
check_dns() {
    local host=$1
    local ip
    ip=$(getent hosts "${host}" 2>/dev/null | awk '{print $1}' || true)
    if [ -z "$ip" ]; then
        warn "DNS ${host} — не резолвится (A-запись не найдена)"
        DNS_OK=false
    elif [ "$ip" != "$SERVER_IP" ]; then
        warn "DNS ${host} → ${ip}, ожидается ${SERVER_IP}"
        DNS_OK=false
    else
        log "DNS: ${host} → ${ip} — OK"
    fi
}

check_dns "${DOMAIN}"

if ! $DNS_OK; then
    echo ""
    warn "A-запись домена ${DOMAIN} не указывает на этот сервер (${SERVER_IP})."
    warn "Certbot не сможет выпустить SSL-сертификат — установка завершится ошибкой."
    echo ""
    echo "  Как добавить A-запись:"
    echo ""
    printf "  %-12s %s\n" "Тип:"   "A"
    printf "  %-12s %s\n" "Имя:"   "${DOMAIN}"
    printf "  %-12s %s\n" "Адрес:" "${SERVER_IP}"
    printf "  %-12s %s\n" "TTL:"   "300 (или минимальное доступное)"
    echo ""
    echo "  После добавления записи подождите 5–30 минут (DNS распространяется)."
    echo "  Затем запустите install.sh снова."
    echo ""
    echo -n "$(echo -e "${YELLOW}[!!]${NC}") Продолжить всё равно (без DNS)? [y/N]: "
    read -r DNS_CONFIRM
    DNS_CONFIRM="${DNS_CONFIRM:-n}"
    if [[ ! "$DNS_CONFIRM" =~ ^[Yy]$ ]]; then
        echo ""
        err "Установка прервана. Настройте A-запись и запустите скрипт снова."
    fi
    echo ""
fi

# ── Создаём директории ────────────────────────────────────
mkdir -p ./config/synapse
mkdir -p ./config/nginx
$USE_ELEMENT    && mkdir -p ./config/element
$USE_CINNY      && mkdir -p ./config/cinny
if $USE_CALLS; then
    mkdir -p ./config/coturn
    mkdir -p ./config/livekit
fi

# ── Функция генерации homeserver.yaml ─────────────────────
generate_homeserver_yaml() {
    local ENABLE_REG="false"
    $OPEN_REGISTRATION && ENABLE_REG="true"

    cat > ./config/synapse/homeserver.yaml << YAML
server_name: "${SERVER_NAME}"
public_baseurl: "https://${DOMAIN}"

listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    resources:
      - names: [client, federation]
        compress: false

database:
  name: psycopg2
  args:
    user: synapse
    password: ${DB_PASS}
    database: synapse
    host: postgres
    port: 5432
    cp_min: 2
    cp_max: 5

media_store_path: /data/media_store
max_upload_size: ${MAX_UPLOAD}

$(if $USE_CALLS; then cat << TURN
turn_uris:
  - "turn:${DOMAIN}:3478?transport=udp"
  - "turn:${DOMAIN}:3478?transport=tcp"
turn_shared_secret: "${TURN_SECRET}"
turn_user_lifetime: 86400000
turn_allow_guests: false
TURN
fi)

log_config: /data/log.config
signing_key_path: /data/${SERVER_NAME}.signing.key

enable_registration: ${ENABLE_REG}
registration_shared_secret: "${REG_SECRET}"
enable_registration_captcha: false

$(case "${FEDERATION_MODE}" in
    closed)
        echo "federation_domain_whitelist: []"
        echo "block_non_local_invites: true"
        echo "allow_public_rooms_over_federation: false"
        ;;
    whitelist)
        echo "block_non_local_invites: true"
        echo "allow_public_rooms_over_federation: false"
        if [ -n "${FEDERATION_SERVERS}" ]; then
            echo "federation_domain_whitelist:"
            echo "${FEDERATION_SERVERS}" | tr ',' '\n' | while IFS= read -r _srv; do
                [ -n "$_srv" ] && echo "  - ${_srv}"
            done
        else
            echo "federation_domain_whitelist: []"
        fi
        ;;
esac)

report_stats: false
suppress_key_server_warning: true

user_directory:
  enabled: true
  search_all_users: true
  prefer_local_users: true

trusted_key_servers:
  - server_name: "matrix.org"

$(if $SMTP_ENABLED; then cat << SMTP
email:
  smtp_host: "${SMTP_HOST}"
  smtp_port: ${SMTP_PORT}
  smtp_user: "${SMTP_USER}"
  smtp_pass: "${SMTP_PASS}"
  notif_from: "Matrix <${SMTP_FROM}>"
  enable_tls: true
  require_transport_security: true
SMTP
fi)

$(if $USE_MINIO; then cat << S3
media_storage_providers:
  - module: s3_storage_provider.S3StorageProviderBackend
    store_local: true
    store_remote: true
    store_copies: true
    config:
      bucket: matrix-media
      endpoint_url: http://minio:9000
      access_key_id: minioadmin
      secret_access_key: ${MINIO_PASS}
S3
fi)
YAML
}

# Генерируем Dockerfile для Synapse если нужен S3-провайдер
if $USE_MINIO; then
    cat > ./config/synapse/Dockerfile << DOCKERFILE
FROM matrixdotorg/synapse:latest
RUN pip install matrix-synapse-s3-storage-provider --quiet
DOCKERFILE
fi

# ── Генерируем конфиги ────────────────────────────────────
info "Генерируем конфигурацию..."

# .env
cat > .env << ENV
SERVER_NAME=${SERVER_NAME}
SYNAPSE_DOMAIN=${DOMAIN}
POSTGRES_USER=synapse
POSTGRES_PASSWORD=${DB_PASS}
POSTGRES_DB=synapse
REGISTRATION_SHARED_SECRET=${REG_SECRET}
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=${MINIO_PASS}
$(if $USE_CALLS; then
echo "TURN_SECRET=${TURN_SECRET}"
echo "LIVEKIT_API_KEY=${LIVEKIT_KEY}"
echo "LIVEKIT_API_SECRET=${LIVEKIT_SECRET}"
fi)
# ── Конфигурация установки (для повторного запуска) ──────
INSTALL_EMAIL=${EMAIL}
INSTALL_ADMIN_USER=${ADMIN_USER}
INSTALL_PORT=${PORT}
INSTALL_MINIO_PORT=${MINIO_PORT}
INSTALL_ADMIN_PORT=${ADMIN_PORT}
INSTALL_CINNY_PORT=${CINNY_PORT}
INSTALL_FLUFFYCHAT_PORT=${FLUFFYCHAT_PORT}
INSTALL_USE_CALLS=${USE_CALLS}
INSTALL_USE_ELEMENT=${USE_ELEMENT}
INSTALL_USE_CINNY=${USE_CINNY}
INSTALL_USE_FLUFFYCHAT=${USE_FLUFFYCHAT}
INSTALL_USE_MINIO=${USE_MINIO}
INSTALL_OPEN_REGISTRATION=${OPEN_REGISTRATION}
INSTALL_MAX_UPLOAD=${MAX_UPLOAD}
INSTALL_SMTP_ENABLED=${SMTP_ENABLED}
INSTALL_SMTP_HOST=${SMTP_HOST}
INSTALL_SMTP_PORT=${SMTP_PORT}
INSTALL_SMTP_USER=${SMTP_USER}
INSTALL_SMTP_FROM=${SMTP_FROM}
INSTALL_BACKUP_LOCAL=${BACKUP_LOCAL}
INSTALL_BACKUP_DAYS=${BACKUP_DAYS}
INSTALL_BACKUP_S3=${BACKUP_S3}
INSTALL_S3_ENDPOINT=${S3_ENDPOINT}
INSTALL_S3_BUCKET=${S3_BUCKET}
INSTALL_S3_DAYS=${S3_DAYS}
INSTALL_BACKUP_MEDIA=${BACKUP_MEDIA}
INSTALL_BACKUP_SCHEDULE=${BACKUP_SCHEDULE}
INSTALL_FEDERATION_MODE=${FEDERATION_MODE}
INSTALL_FEDERATION_SERVERS=${FEDERATION_SERVERS}
ENV

# homeserver.yaml
generate_homeserver_yaml

# Конфиг Element
if $USE_ELEMENT; then
    cat > ./config/element/config.json << JSON
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${DOMAIN}",
            "server_name": "${SERVER_NAME}"
        }
    },
    "brand": "Matrix — Element",
    "default_theme": "light",
    "disable_custom_urls": false,
    "disable_guests": false,
    "default_country_code": "RU"$(if $USE_CALLS; then cat << CALLS
,
    "features": {
        "feature_group_calls": true
    },
    "setting_defaults": {
        "feature_group_calls": true
    },
    "livekit": {
        "service_url": "https://${DOMAIN}/livekit-jwt"
    }
CALLS
fi)
}
JSON
fi

# Конфиг Cinny
if $USE_CINNY; then
    cat > ./config/cinny/config.json << JSON
{
    "defaultHomeserver": 0,
    "homeserverList": [
        {
            "name": "${SERVER_NAME}",
            "url": "https://${DOMAIN}"
        }
    ],
    "allowCustomHomeservers": false
}
JSON
fi

# coturn
if $USE_CALLS; then
    cat > ./config/coturn/turnserver.conf << TURN
listening-port=3478
tls-listening-port=5349
realm=${DOMAIN}
use-auth-secret
static-auth-secret=${TURN_SECRET}
log-file=/var/log/coturn/turnserver.log
simple-log
no-multicast-peers
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
min-port=49152
max-port=49200
no-tls
no-dtls
TURN

    cat > ./config/livekit/livekit.yaml << LIVEKIT
port: 7880
rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 50010
  use_external_ip: true
keys:
  ${LIVEKIT_KEY}: ${LIVEKIT_SECRET}
logging:
  level: info
room:
  auto_create: true
  empty_timeout: 300
LIVEKIT
fi

# ── Генерируем docker-compose.yml ────────────────────────
cat > ./docker-compose.yml << COMPOSE
services:

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - matrix_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

COMPOSE

if $USE_MINIO; then
    cat >> ./docker-compose.yml << COMPOSE
  synapse:
    build:
      context: ./config/synapse
      dockerfile: Dockerfile
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      SYNAPSE_CONFIG_PATH: /data/homeserver.yaml
    volumes:
      - ./config/synapse:/data
      - synapse_media:/data/media_store
    networks:
      - matrix_net
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8008/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s

COMPOSE
else
    cat >> ./docker-compose.yml << COMPOSE
  synapse:
    image: matrixdotorg/synapse:v1.151.0
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      SYNAPSE_CONFIG_PATH: /data/homeserver.yaml
    volumes:
      - ./config/synapse:/data
      - synapse_media:/data/media_store
    networks:
      - matrix_net
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8008/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s

COMPOSE
fi

# Клиентские контейнеры
if $USE_ELEMENT; then
    cat >> ./docker-compose.yml << COMPOSE
  element:
    image: vectorim/element-web:v1.12.15
    restart: unless-stopped
    volumes:
      - ./config/element/config.json:/app/config.json:ro
    networks:
      - matrix_net

COMPOSE
fi

if $USE_CINNY; then
    cat >> ./docker-compose.yml << COMPOSE
  cinny:
    image: ajbura/cinny:v4.11.1
    restart: unless-stopped
    volumes:
      - ./config/cinny/config.json:/app/config.json:ro
    networks:
      - matrix_net

COMPOSE
fi

if $USE_FLUFFYCHAT; then
    cat >> ./docker-compose.yml << COMPOSE
  fluffychat:
    image: ghcr.io/krille-chan/fluffychat:v2.5.1
    restart: unless-stopped
    networks:
      - matrix_net

COMPOSE
fi

# Synapse Admin + certbot + nginx — всегда
cat >> ./docker-compose.yml << COMPOSE
  synapse-admin:
    image: awesometechnologies/synapse-admin:0.11.4
    restart: unless-stopped
    networks:
      - matrix_net

COMPOSE

if $USE_MINIO; then
    cat >> ./docker-compose.yml << COMPOSE
  minio:
    image: minio/minio:RELEASE.2025-09-07T16-13-09Z
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: \${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: \${MINIO_ROOT_PASSWORD}
    volumes:
      - minio_data:/data
    networks:
      - matrix_net
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 30s
      timeout: 10s
      retries: 3

COMPOSE
fi

cat >> ./docker-compose.yml << COMPOSE
  certbot:
    image: certbot/certbot:latest
    restart: unless-stopped
    volumes:
      - certbot_certs:/etc/letsencrypt
      - certbot_www:/var/www/certbot
    entrypoint: /bin/sh -c "trap exit TERM; while :; do certbot renew --webroot -w /var/www/certbot --quiet; sleep 12h & wait \$\${!}; done"
    networks:
      - matrix_net

  nginx:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "${PORT}:443"
      - "${ADMIN_PORT}:${ADMIN_PORT}"
COMPOSE

$USE_MINIO      && echo "      - \"${MINIO_PORT}:${MINIO_PORT}\"" >> ./docker-compose.yml
$USE_CINNY      && echo "      - \"${CINNY_PORT}:${CINNY_PORT}\"" >> ./docker-compose.yml
$USE_FLUFFYCHAT && echo "      - \"${FLUFFYCHAT_PORT}:${FLUFFYCHAT_PORT}\"" >> ./docker-compose.yml

cat >> ./docker-compose.yml << COMPOSE
    volumes:
      - ./config/nginx/matrix.conf:/etc/nginx/conf.d/default.conf:ro
      - certbot_certs:/etc/letsencrypt:ro
      - certbot_www:/var/www/certbot:ro
    networks:
      - matrix_net

COMPOSE

# Звонки — только если включены
if $USE_CALLS; then
    cat >> ./docker-compose.yml << COMPOSE
  coturn:
    image: coturn/coturn:alpine
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./config/coturn/turnserver.conf:/etc/coturn/turnserver.conf:ro
    command: -c /etc/coturn/turnserver.conf

  livekit:
    image: livekit/livekit-server:v1.11.0
    restart: unless-stopped
    command: --config /etc/livekit/livekit.yaml
    volumes:
      - ./config/livekit/livekit.yaml:/etc/livekit/livekit.yaml:ro
    ports:
      - "7880:7880"
      - "7881:7881"
      - "50000-50010:50000-50010/udp"
    networks:
      - matrix_net

  livekit-jwt:
    image: ghcr.io/element-hq/lk-jwt-service:0.4.3
    restart: unless-stopped
    environment:
      LIVEKIT_URL: wss://${DOMAIN}/livekit/
      LIVEKIT_KEY: \${LIVEKIT_API_KEY}
      LIVEKIT_SECRET: \${LIVEKIT_API_SECRET}
    networks:
      - matrix_net

COMPOSE
fi

cat >> ./docker-compose.yml << COMPOSE
networks:
  matrix_net:
    driver: bridge

volumes:
  postgres_data:
  synapse_media:
COMPOSE

$USE_MINIO && echo "  minio_data:" >> ./docker-compose.yml

cat >> ./docker-compose.yml << COMPOSE
  certbot_certs:
  certbot_www:
COMPOSE

# ── Генерируем nginx конфиг ───────────────────────────────
cat > ./config/nginx/matrix.conf << NGINX
# ── HTTP → HTTPS ──────────────────────────────────────────
server {
    listen 80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# ── Synapse (основной домен) ──────────────────────────────
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;

    client_max_body_size ${MAX_UPLOAD};
    proxy_read_timeout   120;

NGINX

if $USE_ELEMENT; then
    cat >> ./config/nginx/matrix.conf << NGINX
    location / {
        proxy_pass http://element:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

NGINX
fi

cat >> ./config/nginx/matrix.conf << NGINX
    location /_matrix {
        proxy_pass http://synapse:8008;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location /_synapse {
        proxy_pass http://synapse:8008;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location /.well-known/matrix/server {
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
        return 200 '{"m.server":"${DOMAIN}:${PORT}"}';
    }

    location /.well-known/matrix/client {
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
        return 200 '{"m.homeserver":{"base_url":"https://${DOMAIN}"}}';
    }

    location /health {
        proxy_pass http://synapse:8008/health;
    }
NGINX

if $USE_CALLS; then
    cat >> ./config/nginx/matrix.conf << NGINX
    location /livekit/ {
        proxy_pass http://livekit:7880/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 3600s;
    }

    location /livekit-jwt/ {
        proxy_pass http://livekit-jwt:8080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
NGINX
fi

cat >> ./config/nginx/matrix.conf << NGINX
}

NGINX

if $USE_CINNY; then
    cat >> ./config/nginx/matrix.conf << NGINX
# ── Cinny :${CINNY_PORT} ──────────────────────────────────────────
server {
    listen ${CINNY_PORT} ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://cinny:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

NGINX
fi

if $USE_FLUFFYCHAT; then
    cat >> ./config/nginx/matrix.conf << NGINX
# ── FluffyChat :${FLUFFYCHAT_PORT} ────────────────────────────────
server {
    listen ${FLUFFYCHAT_PORT} ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://fluffychat:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

NGINX
fi

if $USE_MINIO; then
cat >> ./config/nginx/matrix.conf << NGINX
# ── MinIO Console ─────────────────────────────────────────
server {
    listen ${MINIO_PORT} ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    client_max_body_size ${MAX_UPLOAD};

    location / {
        proxy_pass http://minio:9001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        chunked_transfer_encoding off;
    }
}
NGINX
fi

cat >> ./config/nginx/matrix.conf << NGINX
# ── Synapse Admin ─────────────────────────────────────────
server {
    listen ${ADMIN_PORT} ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://synapse-admin:80/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX

log "Конфигурация сгенерирована"

# ── Signing key ───────────────────────────────────────────
SIGNING_KEY="./config/synapse/${SERVER_NAME}.signing.key"
if [ ! -f "$SIGNING_KEY" ]; then
    info "Генерируем signing key..."
    docker run --rm \
        -v "$(pwd)/config/synapse:/data" \
        -e SYNAPSE_SERVER_NAME=${SERVER_NAME} \
        -e SYNAPSE_REPORT_STATS=no \
        matrixdotorg/synapse:latest generate 2>/dev/null | tail -3 || true
    # Восстанавливаем homeserver.yaml после generate (он перезаписывает)
    generate_homeserver_yaml
    log "Signing key готов"
else
    log "Signing key уже есть"
fi

# ── PostgreSQL ────────────────────────────────────────────
info "Запускаем PostgreSQL..."
docker compose up -d postgres
for i in $(seq 1 30); do
    docker compose exec -T postgres pg_isready -U synapse &>/dev/null && \
        { log "PostgreSQL готов"; break; } || sleep 1
    [ $i -eq 30 ] && err "PostgreSQL не поднялся"
done

# ── SSL сертификат ────────────────────────────────────────
STACK=$(basename $(pwd))
CERT_EXISTS="no"
if docker volume ls | grep -q "${STACK}_certbot_certs"; then
    CERT_EXISTS=$(docker run --rm \
        -v "${STACK}_certbot_certs:/etc/letsencrypt" \
        alpine sh -c \
        "[ -f /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ] && echo yes || echo no" \
        2>/dev/null || echo "no")
fi

if [ "$CERT_EXISTS" = "no" ]; then
    info "Получаем SSL сертификат..."
    cp ./config/nginx/matrix.conf ./config/nginx/matrix.conf.bak
    cp ./config/nginx/matrix-http.conf ./config/nginx/matrix.conf
    docker compose up -d nginx
    sleep 3

    docker run --rm \
        -v "${STACK}_certbot_certs:/etc/letsencrypt" \
        -v "${STACK}_certbot_www:/var/www/certbot" \
        certbot/certbot certonly \
        --webroot --webroot-path=/var/www/certbot \
        --email ${EMAIL} --agree-tos --no-eff-email \
        -d ${DOMAIN} && \
        log "Сертификат получен!" || \
        err "Не удалось получить сертификат. Проверьте DNS и порт 80."

    cp ./config/nginx/matrix.conf.bak ./config/nginx/matrix.conf
    docker compose restart nginx
    sleep 2
    log "nginx перезапущен с HTTPS"
else
    log "Сертификат уже есть"
fi

# ── Запуск стека ──────────────────────────────────────────
info "Запускаем все сервисы..."
docker compose up -d

info "Ждём Synapse (до 60 сек)..."
for i in $(seq 1 60); do
    curl -sf https://${DOMAIN}/_matrix/client/versions &>/dev/null && \
        { log "Synapse готов"; break; } || sleep 1
    [ $i -eq 60 ] && err "Synapse не ответил"
done

# ── Права на media_store ──────────────────────────────────
docker compose exec -T synapse chown -R 991:991 /data/media_store 2>/dev/null && \
    log "Права на media_store выставлены" || true

# ── MinIO bucket ──────────────────────────────────────────
if $USE_MINIO; then
    info "Ждём MinIO..."
    for i in $(seq 1 30); do
        docker compose exec -T minio mc ready local &>/dev/null && \
            { log "MinIO готов"; break; } || sleep 2
        [ $i -eq 30 ] && { warn "MinIO не ответил"; break; }
    done

    docker compose exec -T minio sh -c \
        "mc alias set local http://localhost:9000 minioadmin ${MINIO_PASS} 2>/dev/null && \
         mc mb local/matrix-media 2>/dev/null || true && \
         mc anonymous set download local/matrix-media 2>/dev/null || true" && \
        log "MinIO bucket готов" || warn "MinIO bucket — настройте вручную"
fi

# ── Создание / обновление admin пользователя ─────────────
if [ "$INSTALL_MODE" = "install" ] || [ "$INSTALL_MODE" = "reinstall" ]; then
    if [ -n "$ADMIN_PASS" ]; then
        info "Создаём пользователя ${ADMIN_USER}..."
        docker compose exec -T synapse \
            register_new_matrix_user -c /data/homeserver.yaml \
            -u "${ADMIN_USER}" -p "${ADMIN_PASS}" -a \
            http://localhost:8008 2>/dev/null && \
            log "Пользователь @${ADMIN_USER}:${SERVER_NAME} создан" || \
            warn "Пользователь ${ADMIN_USER} уже существует"
    fi
elif [ "$INSTALL_MODE" = "modify" ] && [ -n "$ADMIN_PASS" ]; then
    info "Обновляем пароль ${ADMIN_USER}..."
    _NEW_HASH=$(docker compose exec -T synapse hash_password -p "$ADMIN_PASS" 2>/dev/null | tr -d '\r\n')
    if [ -n "$_NEW_HASH" ]; then
        docker compose exec -T postgres psql -U synapse -c \
            "UPDATE users SET password_hash='${_NEW_HASH}' WHERE name='@${ADMIN_USER}:${SERVER_NAME}';" \
            2>/dev/null && log "Пароль администратора обновлён" || warn "Не удалось обновить пароль"
    else
        warn "Не удалось изменить пароль (hash_password не ответил)"
    fi
fi

# ── Токен ─────────────────────────────────────────────────
ADMIN_TOKEN=$(curl -sf -X POST https://${DOMAIN}/_matrix/client/v3/login \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"m.login.password\",\"user\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}" \
    2>/dev/null | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

# ── Бэкапы ────────────────────────────────────────────────
if $BACKUP_ENABLED; then
    info "Настраиваем бэкапы..."
    INSTALL_DIR=$(pwd)

    cat > ./backup.sh << BACKUP
#!/bin/bash
# B2B-чат — скрипт резервного копирования
# Сгенерирован автоматически

DOMAIN="${DOMAIN}"
DB_PASS="${DB_PASS}"
INSTALL_DIR="${INSTALL_DIR}"
BACKUP_LOCAL="${BACKUP_LOCAL}"
BACKUP_DAYS="${BACKUP_DAYS}"
BACKUP_MEDIA="${BACKUP_MEDIA}"
S3_ENDPOINT="${S3_ENDPOINT}"
S3_BUCKET="${S3_BUCKET}"
S3_ACCESS_KEY="${S3_ACCESS_KEY}"
S3_SECRET_KEY="${S3_SECRET_KEY}"
S3_DAYS="${S3_DAYS}"

DATE=\$(date +%Y%m%d_%H%M%S)
TMP_DIR=\$(mktemp -d)
ARCHIVE="\${TMP_DIR}/matrix_\${DATE}.tar.gz"

cd "\${INSTALL_DIR}"

echo "[\$(date)] Начало бэкапа..."

# Дамп PostgreSQL
echo "[\$(date)] Дамп PostgreSQL..."
docker compose exec -T postgres pg_dump -U synapse synapse > "\${TMP_DIR}/postgres_\${DATE}.sql" || {
    echo "[\$(date)] ОШИБКА: не удалось сделать дамп PostgreSQL"
    rm -rf "\${TMP_DIR}"
    exit 1
}

# Signing key и конфиги (критично)
echo "[\$(date)] Бэкап конфигов..."
cp -r ./config/synapse "\${TMP_DIR}/synapse_config"

# Медиафайлы (опционально)
if [ "\${BACKUP_MEDIA}" = "true" ]; then
    echo "[\$(date)] Бэкап медиафайлов..."
    STACK=\$(basename "\$(pwd)")
    docker run --rm \
        -v "\${STACK}_synapse_media:/data/media_store" \
        -v "\${TMP_DIR}:/backup" \
        alpine tar -czf /backup/media_\${DATE}.tar.gz /data/media_store 2>/dev/null || \
        echo "[\$(date)] ПРЕДУПРЕЖДЕНИЕ: не удалось забэкапить медиафайлы"
fi

# Архивируем всё
echo "[\$(date)] Создаём архив..."
tar -czf "\${ARCHIVE}" -C "\${TMP_DIR}" . 2>/dev/null

# Локальный бэкап
if [ -n "\${BACKUP_LOCAL}" ]; then
    mkdir -p "\${BACKUP_LOCAL}"
    cp "\${ARCHIVE}" "\${BACKUP_LOCAL}/"
    echo "[\$(date)] Бэкап сохранён: \${BACKUP_LOCAL}/\$(basename \${ARCHIVE})"

    # Удаляем старые
    find "\${BACKUP_LOCAL}" -name "matrix_*.tar.gz" -mtime +\${BACKUP_DAYS} -delete 2>/dev/null || true
    echo "[\$(date)] Удалены бэкапы старше \${BACKUP_DAYS} дней"
fi

# S3 бэкап
if [ -n "\${S3_BUCKET}" ]; then
    echo "[\$(date)] Загружаем в S3..."
    docker run --rm \
        -e AWS_ACCESS_KEY_ID="\${S3_ACCESS_KEY}" \
        -e AWS_SECRET_ACCESS_KEY="\${S3_SECRET_KEY}" \
        -v "\${TMP_DIR}:/backup" \
        amazon/aws-cli:latest \
        s3 cp "/backup/\$(basename \${ARCHIVE})" \
        "s3://\${S3_BUCKET}/\$(basename \${ARCHIVE})" \
        --endpoint-url "\${S3_ENDPOINT}" 2>/dev/null && \
        echo "[\$(date)] S3: загружено" || \
        echo "[\$(date)] S3: ОШИБКА загрузки"

    # Удаляем старые из S3
    if [ "\${S3_DAYS}" -gt 0 ] 2>/dev/null; then
        CUTOFF=\$(date -d "-\${S3_DAYS} days" +%Y-%m-%d 2>/dev/null || \
                  date -v -\${S3_DAYS}d +%Y-%m-%d 2>/dev/null)
        if [ -n "\${CUTOFF}" ]; then
            docker run --rm \
                -e AWS_ACCESS_KEY_ID="\${S3_ACCESS_KEY}" \
                -e AWS_SECRET_ACCESS_KEY="\${S3_SECRET_KEY}" \
                amazon/aws-cli:latest \
                s3 ls "s3://\${S3_BUCKET}/" --endpoint-url "\${S3_ENDPOINT}" 2>/dev/null | \
                awk '{print \$4}' | while read f; do
                    fdate=\$(echo "\$f" | grep -oP '\d{8}' | head -1 | sed 's/\(....\)\(..\)\(..\)/\1-\2-\3/')
                    [ "\$fdate" "<" "\$CUTOFF" ] && \
                    docker run --rm \
                        -e AWS_ACCESS_KEY_ID="\${S3_ACCESS_KEY}" \
                        -e AWS_SECRET_ACCESS_KEY="\${S3_SECRET_KEY}" \
                        amazon/aws-cli:latest \
                        s3 rm "s3://\${S3_BUCKET}/\${f}" --endpoint-url "\${S3_ENDPOINT}" 2>/dev/null || true
                done
        fi
    fi
fi

rm -rf "\${TMP_DIR}"
echo "[\$(date)] Бэкап завершён"
BACKUP

    chmod +x ./backup.sh
    log "backup.sh создан"

    # Настраиваем cron
    if [ "$BACKUP_SCHEDULE" = "2" ]; then
        CRON_SCHEDULE="0 3,15 * * *"
        CRON_DESC="каждые 12 часов (3:00 и 15:00)"
    else
        CRON_SCHEDULE="0 3 * * *"
        CRON_DESC="ежедневно в 3:00"
    fi

    CRON_JOB="${CRON_SCHEDULE} root ${INSTALL_DIR}/backup.sh >> /var/log/matrix-backup.log 2>&1"

    # Добавляем или обновляем cron задачу
    if [ -f /etc/cron.d/matrix-backup ]; then
        rm -f /etc/cron.d/matrix-backup
    fi
    echo "$CRON_JOB" > /etc/cron.d/matrix-backup
    chmod 644 /etc/cron.d/matrix-backup

    log "Бэкапы по расписанию: ${CRON_DESC}"
    log "Лог бэкапов: /var/log/matrix-backup.log"
fi

# ── Итог ─────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                    СТЕК ЗАПУЩЕН                         ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
printf "║  Synapse:    https://%-36s ║\n" "${DOMAIN}"
$USE_ELEMENT    && printf "║  Element:    https://%-36s ║\n" "${DOMAIN}"
$USE_CINNY      && printf "║  Cinny:      https://${DOMAIN}:%-$((36 - ${#DOMAIN}))s ║\n" "${CINNY_PORT}"
$USE_FLUFFYCHAT && printf "║  FluffyChat: https://${DOMAIN}:%-$((36 - ${#DOMAIN}))s ║\n" "${FLUFFYCHAT_PORT}"
$USE_MINIO      && printf "║  MinIO:      https://${DOMAIN}:%-$((36 - ${#DOMAIN}))s ║\n" "${MINIO_PORT}"
printf "║  Admin UI:   https://${DOMAIN}:%-$((36 - ${#DOMAIN}))s ║\n" "${ADMIN_PORT}"
$USE_CALLS && echo "║  STUN/TURN:  ${DOMAIN}:3478                              ║"
echo "║                                                          ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  Пользователи: @user:%-36s ║\n" "${SERVER_NAME}"
printf "║  Логин:   ${ADMIN_USER} / ${ADMIN_PASS}%-$((57 - ${#ADMIN_USER} - ${#ADMIN_PASS}))s ║\n" ""
$USE_MINIO && printf "║  MinIO:   minioadmin / ${MINIO_PASS}%-$((34 - ${#MINIO_PASS}))s ║\n" ""
echo "║                                                          ║"
if $OPEN_REGISTRATION; then
echo "║  Регистрация: открытая                                   ║"
else
echo "║  Регистрация: только через администратора                ║"
fi
if $SMTP_ENABLED; then
printf "║  Email:   %-47s ║\n" "${SMTP_HOST}:${SMTP_PORT}"
fi
if $BACKUP_ENABLED; then
[ -n "$BACKUP_LOCAL" ] && printf "║  Бэкап:   %-47s ║\n" "${BACKUP_LOCAL}"
fi
echo "║  SSL автообновляется каждые 12 часов                     ║"
echo "╚══════════════════════════════════════════════════════════╝"

if [ -n "$ADMIN_TOKEN" ]; then
    echo ""
    echo "Токен для Synapse Admin UI:"
    echo "$ADMIN_TOKEN"
fi

# ── Сохраняем порты ──────────────────────────────────────
cat > ./ports.txt << PORTS
# B2B-чат — порты
# Сгенерировано: $(date)

Element/Synapse : https://${DOMAIN}
$(  $USE_MINIO      && echo "MinIO Console   : https://${DOMAIN}:${MINIO_PORT}")
Synapse Admin   : https://${DOMAIN}:${ADMIN_PORT}
$(  $USE_CINNY      && echo "Cinny           : https://${DOMAIN}:${CINNY_PORT}")
$(  $USE_FLUFFYCHAT && echo "FluffyChat      : https://${DOMAIN}:${FLUFFYCHAT_PORT}")
PORTS
log "Порты сохранены в ./ports.txt"

echo ""
echo "Статус:     ./manage.sh status"
echo "Логи:       ./manage.sh logs"
echo "Остановить: ./manage.sh stop"
echo "Здоровье:   ./manage.sh health"
echo "Порты:      cat ports.txt"
echo ""

# ── Что делать дальше ─────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                 Что делать дальше                       ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
echo "║  1. Откройте браузер:                                    ║"
printf "║     %-53s ║\n" "https://${DOMAIN}"
echo "║                                                          ║"
printf "║  2. Войдите: @%-44s ║\n" "${ADMIN_USER}:${SERVER_NAME}"
echo "║     (пароль — тот что вы указали при установке)          ║"
echo "║                                                          ║"
echo "║  3. Создайте аккаунты для сотрудников:                   ║"
printf "║     %-53s ║\n" "https://${DOMAIN}:${ADMIN_PORT}"
echo "║     Вставьте токен (показан выше) при входе в Admin UI   ║"
echo "║                                                          ║"
echo "║  4. Скачайте Element на телефон:                         ║"
echo "║     iOS     — App Store  → Element                       ║"
echo "║     Android — Play Store → Element                       ║"
printf "║     Сервер: %-46s ║\n" "https://${DOMAIN}"
echo "║                                                          ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Управление: ./manage.sh --help                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
