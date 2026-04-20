#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log()   { echo -e "${GREEN}[OK]${NC} $*"; }
info()  { echo -e "${BLUE}[..]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!!]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC} $*"; exit 1; }
title() { echo -e "\n${CYAN}$*${NC}"; }

# ── Вспомогательные функции ввода ─────────────────────────
ask() {
    local prompt="$1" default="$2" result
    if [ -n "$default" ]; then
        read -rp "$(echo -e "${BLUE}?${NC} ${prompt} [${default}]: ")" result </dev/tty
        echo "${result:-$default}"
    else
        read -rp "$(echo -e "${BLUE}?${NC} ${prompt}: ")" result </dev/tty
        echo "$result"
    fi
}

ask_secret() {
    local prompt="$1" result
    read -rsp "$(echo -e "${BLUE}?${NC} ${prompt}: ")" result </dev/tty
    echo "" >&2
    echo "$result"
}

ask_yn() {
    local prompt="$1" default="${2:-n}" result
    read -rp "$(echo -e "${BLUE}?${NC} ${prompt} (y - да, n - нет) [${default}]: ")" result </dev/tty
    result="${result:-$default}"
    [[ "$result" =~ ^[Yy]$ ]]
}

# ── Хелпер: читаем значение из существующего .env ─────────
INSTALL_DIR="/opt/b2b-chat"
IGNORE_PREV_CONFIG=false

prev_val() {
    local key="$1" default="${2:-}"
    if [ "$IGNORE_PREV_CONFIG" = "true" ]; then
        echo "$default"
        return
    fi
    if [ -f "${INSTALL_DIR}/.env" ]; then
        local val
        val=$(grep "^${key}=" "${INSTALL_DIR}/.env" 2>/dev/null | cut -d= -f2- || true)
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

# true/false → y/n для ask_yn
prev_bool() {
    local val
    val=$(prev_val "$1" "$2")
    [ "$val" = "true" ] && echo "y" || echo "n"
}

# ════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              B2B-чат — установка                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Проверка существующей установки ──────────────────────
MODIFY_MODE=false
REINSTALL_FLAG=""

if [ -f "${INSTALL_DIR}/.env" ]; then
    EXISTING_DOMAIN=$(prev_val SYNAPSE_DOMAIN "")
    echo ""
    warn "Обнаружена существующая установка B2B-чат."
    [ -n "$EXISTING_DOMAIN" ] && warn "Домен: ${EXISTING_DOMAIN}"
    echo ""
    echo "  [1] Изменить настройки  (данные сохранятся)"
    echo "  [2] Переустановить полностью  (все данные будут удалены)"
    echo "  [3] Отмена"
    echo ""
    read -rp "$(echo -e "${BLUE}>>${NC} Выбор [1]: ")" _CHOICE
    _CHOICE="${_CHOICE:-1}"

    case "$_CHOICE" in
        2)
            echo ""
            warn "Будут удалены все контейнеры и данные: БД, медиафайлы, сертификаты."
            read -rp "$(echo -e "${RED}[!!]${NC} Введите 'yes' для подтверждения: ")" _CONFIRM
            [ "$_CONFIRM" != "yes" ] && { warn "Отменено."; exit 0; }
            REINSTALL_FLAG="--reinstall"
            IGNORE_PREV_CONFIG=true
            ;;
        3) warn "Отменено."; exit 0 ;;
        *) MODIFY_MODE=true ;;
    esac
    echo ""
fi

# ── Режим установки ───────────────────────────────────────
ADVANCED_SETUP=false
echo "  Выберите режим установки:"
echo ""
echo "  [1] Установка с рекомендуемыми параметрами (быстро и безопасно)"
echo "  [2] Расширенная настройка (ручной выбор параметров)"
echo ""
read -rp "$(echo -e "${BLUE}>>${NC} Выбор [1]: ")" INSTALL_MODE_CHOICE
INSTALL_MODE_CHOICE="${INSTALL_MODE_CHOICE:-1}"
if [ "$INSTALL_MODE_CHOICE" = "2" ]; then
    ADVANCED_SETUP=true
    log "Режим: ручной выбор параметров"
else
    log "Режим: установка с рекомендуемыми параметрами"
fi

# ── Требования к серверу (только при первой установке/переустановке) ──
if [ "$MODIFY_MODE" = "false" ]; then
    info "Проверяем окружение сервера..."
    echo ""
    echo "  Минимальные требования к серверу:"
    echo ""
    echo "  ┌─────────────────┬───────┬────────┬──────────┐"
    echo "  │ Пользователей   │  CPU  │  RAM   │  Диск    │"
    echo "  ├─────────────────┼───────┼────────┼──────────┤"
    echo "  │ до 50           │  2    │  2 GB  │  20 GB   │"
    echo "  │ до 200          │  2    │  4 GB  │  50 GB   │"
    echo "  │ до 500          │  4    │  8 GB  │  100 GB  │"
    echo "  │ более 500       │  4+   │  16 GB │  200 GB+ │"
    echo "  ├─────────────────┼───────┼────────┼──────────┤"
    echo "  │ + звонки/видео  │  +1   │  +2 GB │  —       │"
    echo "  └─────────────────┴───────┴────────┴──────────┘"
    echo ""
    echo "  OS: Ubuntu 20.04 / 22.04 LTS"
    echo "  Открытые порты: 80, 443, 8448 (federation)"
    echo "  Со звонками:    дополнительно 3478 UDP/TCP, 49152-49200 UDP"
    echo ""
fi

# ════════════════════════════════════════════════════════════
# ЧАСТЬ 1 — ТЕХНИЧЕСКОЕ ОКРУЖЕНИЕ
# ════════════════════════════════════════════════════════════

if $ADVANCED_SETUP; then
    title "▶ Часть 1 из 2 — Техническое окружение"
else
    title "▶ Установка с рекомендуемыми параметрами"
fi

# ── Блок 1: Проверка окружения ────────────────────────────
echo ""
info "Проверяем окружение..."
echo ""

OS_NAME=$(lsb_release -is 2>/dev/null || echo "Unknown")
OS_VER=$(lsb_release -rs 2>/dev/null || echo "0")

if [ "$OS_NAME" = "Ubuntu" ]; then
    if awk "BEGIN {exit !($OS_VER >= 20.04)}"; then
        log "OS: Ubuntu ${OS_VER} — OK"
    else
        warn "OS: Ubuntu ${OS_VER} — рекомендуется 20.04+"
    fi
else
    warn "OS: ${OS_NAME} — рекомендуется Ubuntu 20.04+"
fi

CPU_CORES=$(nproc)
[ "$CPU_CORES" -ge 2 ] && log "CPU: ${CPU_CORES} ядер — OK" || warn "CPU: ${CPU_CORES} ядро — рекомендуется минимум 2"

# Для расчётов проверяем awk и при необходимости ставим gawk
if ! command -v awk >/dev/null 2>&1; then
    warn "Пакет awk не найден — устанавливаем gawk..."
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y gawk >/dev/null 2>&1 || warn "Не удалось установить gawk, продолжаем установку"
fi

RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
RAM_GB=$(awk "BEGIN {printf \"%.1f\", ${RAM_MB}/1024}")
if   [ "$RAM_MB" -ge 3800 ]; then log "RAM: ${RAM_GB} GB — OK"
elif [ "$RAM_MB" -ge 1800 ]; then warn "RAM: ${RAM_GB} GB — минимум, рекомендуется 4 GB"
else warn "RAM: ${RAM_GB} GB — недостаточно, рекомендуется минимум 2 GB"
fi

DISK_FREE_GB=$(df -BG / | awk 'NR==2{gsub("G",""); print $4}')
[ "$DISK_FREE_GB" -ge 20 ] && log "Диск: ${DISK_FREE_GB} GB свободно — OK" || warn "Диск: ${DISK_FREE_GB} GB свободно — рекомендуется минимум 20 GB"

EXTERNAL_IP=$(curl -sf --max-time 5 https://api.ipify.org || \
              curl -sf --max-time 5 https://ifconfig.me || \
              hostname -I | awk '{print $1}')
log "Внешний IP: ${EXTERNAL_IP}"

echo ""
info "Проверяем порты..."
PORTS_BUSY=""
for P in 80 443 8448 3478; do
    if ss -tlnp 2>/dev/null | grep -q ":${P} " || \
       netstat -tlnp 2>/dev/null | grep -q ":${P} "; then
        PORTS_BUSY="${PORTS_BUSY} ${P}"
    fi
done
[ -z "$PORTS_BUSY" ] && log "Порты: все свободны — OK" || \
    { warn "Порты заняты:${PORTS_BUSY}"; warn "Убедитесь что порты будут освобождены перед запуском"; }

echo ""
warn "Если ваш сервер в облаке (Hetzner, Timeweb, VK Cloud, Selectel и др.) —"
warn "откройте порты 80, 443, 8448 также в панели провайдера (Firewall / Security Groups)."
warn "Настройка ufw на сервере не заменяет облачный файрвол."
echo ""

# ── Блок 2: Домен и SSL ───────────────────────────────────
if $ADVANCED_SETUP; then
    title "Блок 2 — Домен и SSL"
fi
echo ""

DOMAIN=$(ask "Укажите домен, на котором будет работать чат" "$(prev_val SYNAPSE_DOMAIN 'chat.mycompany.ru')")
EMAIL=$(ask "Укажите Email администратора для выпуска сертификата SSL" "$(prev_val INSTALL_EMAIL 'admin@example.com')")

echo ""
info "Проверяем A-запись домена..."
DOMAIN_IPS=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')

if [ -z "$DOMAIN_IPS" ]; then
    warn "A-запись для ${DOMAIN} не найдена."
    warn "Добавьте A-запись на IP вашего сервера: ${EXTERNAL_IP}"
    if ! ask_yn "Подтвердите продолжение без корректной A-записи?" "n"; then
        warn "Установка отменена. Настройте A-запись и запустите снова."
        exit 0
    fi
elif [ -z "$EXTERNAL_IP" ]; then
    warn "Не удалось определить внешний IP сервера. Проверить A-запись автоматически не удалось."
elif [[ " ${DOMAIN_IPS} " == *" ${EXTERNAL_IP} "* ]]; then
    log "A-запись: ${DOMAIN} → ${EXTERNAL_IP} — OK"
else
    warn "A-запись ${DOMAIN} указывает на: ${DOMAIN_IPS}"
    warn "Ожидаемый IP сервера: ${EXTERNAL_IP}"
    if ! ask_yn "Подтвердите продолжение с некорректной A-записью?" "n"; then
        warn "Установка отменена. Исправьте A-запись и запустите снова."
        exit 0
    fi
fi

if $ADVANCED_SETUP; then
    echo ""
    info "Домен пользователей определяет формат логинов в Matrix."
    info "Если оставить как домен сервера, при авторизации пользователи будут указывать логин вида: @ivan:${DOMAIN}"
    info "Если указать отдельный домен (например, company.ru), при авторизации пользователи будут указывать логин вида: @ivan:company.ru"
    echo ""
fi
_PREV_SNAME=$(prev_val SERVER_NAME "")
_SAME_DEFAULT="y"
[ -n "$_PREV_SNAME" ] && [ "$_PREV_SNAME" != "$(prev_val SYNAPSE_DOMAIN '')" ] && _SAME_DEFAULT="n"

if $ADVANCED_SETUP; then
    if ask_yn "Использовать домен сервера для логинов пользователей?" "$_SAME_DEFAULT"; then
        SERVER_NAME="$DOMAIN"
        log "Домен пользователей: @user:${SERVER_NAME}"
    else
        SERVER_NAME=$(ask "Укажите домен пользователей" "$(prev_val SERVER_NAME 'example.com')")
        log "Пользователи будут: @user:${SERVER_NAME}"
    fi
else
    SERVER_NAME="$DOMAIN"
    log "Домен пользователей: @user:${SERVER_NAME} (рекомендуемый режим)"
fi

# ── Блок 3: Звонки ────────────────────────────────────────
if $ADVANCED_SETUP; then
    title "Блок 3 — Звонки и видео"
fi
echo ""

USE_CALLS=true
if $ADVANCED_SETUP; then
    USE_CALLS=false
    if ask_yn "Подтвердите включение звонков и видео (Coturn + LiveKit)?" "$(prev_bool INSTALL_USE_CALLS 'y')"; then
        USE_CALLS=true
        log "Звонки: включены"
    else
        log "Звонки: отключены"
    fi
else
    log "Звонки: включены (рекомендуемый режим)"
fi

# ── Блок 4: Клиент ────────────────────────────────────────
if $ADVANCED_SETUP; then
    title "Блок 4 — Веб-клиент"
fi
echo ""

USE_ELEMENT=false; USE_CINNY=false; USE_FLUFFYCHAT=false; USE_B2B=false

if $ADVANCED_SETUP; then
    # Определяем дефолт клиентского режима из предыдущей установки
    _PREV_USE_ELEMENT=$(prev_val INSTALL_USE_ELEMENT "")
    _CLIENT_MODE_DEFAULT="1"
    [ "$_PREV_USE_ELEMENT" = "true" ] && _CLIENT_MODE_DEFAULT="2"
    [ "$(prev_val INSTALL_USE_CINNY '')" = "true" ]      && _CLIENT_MODE_DEFAULT="2"
    [ "$(prev_val INSTALL_USE_FLUFFYCHAT '')" = "true" ] && _CLIENT_MODE_DEFAULT="2"

    echo "  Для общения с пользователями доступны два варианта:"
    echo ""
    echo "  [1] Использовать B2B-связи — готовый корпоративный клиент"
    echo "      (ничего устанавливать не нужно, можно сразу начать работу)"
    echo "      (веб-версия: https://chat.b2b-links.ru)"
    echo "  [2] Установить клиента на свой сервер"
    echo "      (полный контроль, своя инфраструктура)"
    echo ""
    read -rp "$(echo -e "${BLUE}>>${NC} Выбор [${_CLIENT_MODE_DEFAULT}]: ")" CLIENT_MODE
    CLIENT_MODE="${CLIENT_MODE:-${_CLIENT_MODE_DEFAULT}}"

    if [ "$CLIENT_MODE" = "1" ]; then
        USE_B2B=true
        log "Клиент: B2B-связи"
    else
        # Формируем дефолт из предыдущего выбора
        _PREV_CLIENTS=""
        [ "$(prev_val INSTALL_USE_ELEMENT '')" = "true" ]    && _PREV_CLIENTS="${_PREV_CLIENTS}1 "
        [ "$(prev_val INSTALL_USE_CINNY '')" = "true" ]      && _PREV_CLIENTS="${_PREV_CLIENTS}2 "
        [ "$(prev_val INSTALL_USE_FLUFFYCHAT '')" = "true" ] && _PREV_CLIENTS="${_PREV_CLIENTS}3 "
        _PREV_CLIENTS="${_PREV_CLIENTS:-1}"

        echo ""
        echo "  Какие клиенты установить?"
        echo "  [1] Element"
        echo "  [2] Cinny"
        echo "  [3] FluffyChat"
        echo "  [4] Все"
        echo ""
        read -rp "$(echo -e "${BLUE}>>${NC} Выбор (можно несколько, например: 1 2) [${_PREV_CLIENTS}]: ")" CLIENTS_INPUT
        CLIENTS_INPUT="${CLIENTS_INPUT:-${_PREV_CLIENTS}}"

        if echo "$CLIENTS_INPUT" | grep -q "4"; then
            USE_ELEMENT=true; USE_CINNY=true; USE_FLUFFYCHAT=true
        else
            echo "$CLIENTS_INPUT" | grep -q "1" && USE_ELEMENT=true
            echo "$CLIENTS_INPUT" | grep -q "2" && USE_CINNY=true
            echo "$CLIENTS_INPUT" | grep -q "3" && USE_FLUFFYCHAT=true
        fi
        ! $USE_ELEMENT && ! $USE_CINNY && ! $USE_FLUFFYCHAT && USE_ELEMENT=true

        CLIENTS_STR=""
        $USE_ELEMENT    && CLIENTS_STR="${CLIENTS_STR} Element"
        $USE_CINNY      && CLIENTS_STR="${CLIENTS_STR} Cinny"
        $USE_FLUFFYCHAT && CLIENTS_STR="${CLIENTS_STR} FluffyChat"
        log "Клиенты:${CLIENTS_STR}"
    fi
else
    USE_B2B=false
    USE_ELEMENT=true
    USE_CINNY=false
    USE_FLUFFYCHAT=false
    log "Клиент: Element (рекомендуемый режим)"
fi

# ── Блок 5: Хранилище медиа ───────────────────────────────
if $ADVANCED_SETUP; then
    title "Блок 5 — Хранилище медиа"
fi
echo ""

USE_MINIO=false
if $ADVANCED_SETUP; then
    if ask_yn "Подтвердите включение S3-хранилища медиа (MinIO)?" "$(prev_bool INSTALL_USE_MINIO 'n')"; then
        USE_MINIO=true
        log "MinIO: включен"
    else
        log "MinIO: отключен"
        # Сбрасываем порт, чтобы не протаскивать старое значение
        MINIO_PORT=""
    fi
else
    log "MinIO: отключен (рекомендуемый режим)"
    MINIO_PORT=""
fi

# ── Блок 6: Порты ─────────────────────────────────────────
if $ADVANCED_SETUP; then
    title "Блок 6 — Порты"
fi
echo ""

# Читаем текущие порты или используем дефолты
PORT=$(prev_val INSTALL_PORT "443")
MINIO_PORT=$(prev_val INSTALL_MINIO_PORT "")
ADMIN_PORT=$(prev_val INSTALL_ADMIN_PORT "")
CINNY_PORT=$(prev_val INSTALL_CINNY_PORT "")
FLUFFYCHAT_PORT=$(prev_val INSTALL_FLUFFYCHAT_PORT "")

if $ADVANCED_SETUP; then
    if $MODIFY_MODE; then
        echo "  Текущие порты:"
        echo "  Element/Synapse: ${PORT}"
        $USE_MINIO && echo "  MinIO Console:   ${MINIO_PORT:-случайный}"
        echo "  Synapse Admin:   ${ADMIN_PORT}"
        $USE_CINNY      && echo "  Cinny:           ${CINNY_PORT}"
        $USE_FLUFFYCHAT && echo "  FluffyChat:      ${FLUFFYCHAT_PORT}"
    else
        echo "  Стандартные порты:"
        echo "  Element/Synapse: 443"
        $USE_MINIO && echo "  MinIO Console:   случайный (20000–60000)"
        echo "  Synapse Admin:   случайный (20000–60000)"
        $USE_CINNY      && echo "  Cinny:           случайный (20000–60000)"
        $USE_FLUFFYCHAT && echo "  FluffyChat:      случайный (20000–60000)"
    fi
    echo ""
fi

if $ADVANCED_SETUP; then
    if ask_yn "Подтвердите: изменить порты?" "n"; then
        PORT=$(ask "Укажите порт Element/Synapse" "$PORT")
        if $USE_MINIO; then
            MINIO_PORT=$(ask "Укажите порт MinIO Console" "${MINIO_PORT:-случайный}")
            [ "${MINIO_PORT}" = "случайный" ] && MINIO_PORT=""
        fi
        ADMIN_PORT=$(ask "Укажите порт Synapse Admin" "${ADMIN_PORT:-случайный}")
        [ "${ADMIN_PORT}" = "случайный" ] && ADMIN_PORT=""
        if $USE_CINNY; then
            CINNY_PORT=$(ask "Укажите порт Cinny" "${CINNY_PORT:-случайный}")
            [ "${CINNY_PORT}" = "случайный" ] && CINNY_PORT=""
        fi
        if $USE_FLUFFYCHAT; then
            FLUFFYCHAT_PORT=$(ask "Укажите порт FluffyChat" "${FLUFFYCHAT_PORT:-случайный}")
            [ "${FLUFFYCHAT_PORT}" = "случайный" ] && FLUFFYCHAT_PORT=""
        fi
    fi
fi

# ── Блок 7: Бэкапы ───────────────────────────────────────
if $ADVANCED_SETUP; then
    title "Блок 7 — Резервное копирование"
fi
echo ""

BACKUP_ENABLED=false
BACKUP_LOCAL=false
BACKUP_S3=false
BACKUP_DIR=$(prev_val INSTALL_BACKUP_LOCAL "/opt/backups/matrix")
BACKUP_DAYS=$(prev_val INSTALL_BACKUP_DAYS "30")
BACKUP_MEDIA=false
BACKUP_SCHEDULE=$(prev_val INSTALL_BACKUP_SCHEDULE "1")
S3_ENDPOINT=$(prev_val INSTALL_S3_ENDPOINT "storage.yandexcloud.net")
S3_BUCKET=$(prev_val INSTALL_S3_BUCKET "matrix-backup")
S3_ACCESS_KEY=""
S3_SECRET_KEY=""
S3_DAYS=$(prev_val INSTALL_S3_DAYS "90")

_BACKUP_DEFAULT="n"
[ -n "$(prev_val INSTALL_BACKUP_LOCAL '')" ] && _BACKUP_DEFAULT="y"
[ "$(prev_val INSTALL_BACKUP_S3 '')" = "true" ] && _BACKUP_DEFAULT="y"

if $ADVANCED_SETUP; then
    if ask_yn "Подтвердите настройку автоматических бэкапов?" "$_BACKUP_DEFAULT"; then
        BACKUP_ENABLED=true

        # Определяем дефолт режима бэкапа
        # INSTALL_BACKUP_LOCAL хранит путь (не "true"), INSTALL_BACKUP_S3 — "true/false"
        _HAS_LOCAL=""; [ -n "$(prev_val INSTALL_BACKUP_LOCAL '')" ] && _HAS_LOCAL="y"
        _HAS_S3="";    [ "$(prev_val INSTALL_BACKUP_S3 '')" = "true" ] && _HAS_S3="y"
        _BMODE_DEFAULT="1"
        [ -n "$_HAS_LOCAL" ] && [ -n "$_HAS_S3" ] && _BMODE_DEFAULT="3"
        [ -n "$_HAS_S3" ]    && [ -z "$_HAS_LOCAL" ] && _BMODE_DEFAULT="2"

    echo ""
    echo "  Куда сохранять бэкапы?"
    echo "  [1] Локально на этом сервере"
    echo "  [2] S3-совместимое хранилище"
    echo "  [3] Оба варианта"
    echo ""
    read -rp "$(echo -e "${BLUE}>>${NC} Выбор [${_BMODE_DEFAULT}]: ")" BACKUP_MODE
    BACKUP_MODE="${BACKUP_MODE:-${_BMODE_DEFAULT}}"

    if [ "$BACKUP_MODE" = "1" ] || [ "$BACKUP_MODE" = "3" ]; then
        BACKUP_LOCAL=true
        BACKUP_DIR=$(ask "Укажите папку для бэкапов" "$BACKUP_DIR")
        BACKUP_DAYS=$(ask "Укажите срок хранения локальных бэкапов (дней)" "$BACKUP_DAYS")
    fi

    if [ "$BACKUP_MODE" = "2" ] || [ "$BACKUP_MODE" = "3" ]; then
        BACKUP_S3=true
        echo ""
        S3_ENDPOINT=$(ask "Укажите S3 Endpoint" "$S3_ENDPOINT")
        S3_BUCKET=$(ask "Укажите S3 Bucket" "$S3_BUCKET")
        S3_ACCESS_KEY=$(ask "Укажите Access Key" "")
        S3_SECRET_KEY=$(ask_secret "Укажите Secret Key")
        S3_DAYS=$(ask "Укажите срок хранения в S3 (дней)" "$S3_DAYS")
    fi

    echo ""
    if ask_yn "Подтвердите бэкап медиафайлов?" "$(prev_bool INSTALL_BACKUP_MEDIA 'n')"; then
        BACKUP_MEDIA=true
    fi

    echo ""
    echo "  Расписание бэкапов:"
    echo "  [1] Каждый день в 3:00 (рекомендуется)"
    echo "  [2] Каждые 12 часов"
    echo ""
    read -rp "$(echo -e "${BLUE}>>${NC} Выбор [${BACKUP_SCHEDULE}]: ")" BACKUP_SCHEDULE
    BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-1}"

        log "Бэкапы: настроены"
    else
        echo ""
        warn "Без бэкапов данные невозможно восстановить при сбое сервера."
        warn "Signing key — критичный файл, его потеря нарушит работу федерации."
        echo ""
        if ! ask_yn "Подтвердите продолжение без бэкапов?" "n"; then
            BACKUP_ENABLED=true
            BACKUP_LOCAL=true
            BACKUP_DIR="/opt/backups/matrix"
            warn "Включены локальные бэкапы по умолчанию"
        fi
    fi
else
    BACKUP_ENABLED=true
    BACKUP_LOCAL=true
    BACKUP_DIR="/opt/backups/matrix"
    BACKUP_DAYS="30"
    BACKUP_S3=false
    BACKUP_MEDIA=false
    BACKUP_SCHEDULE="1"
    log "Бэкапы: локальные включены (рекомендуемый режим)"
fi

# ════════════════════════════════════════════════════════════
# ЧАСТЬ 2 — НАСТРОЙКА СЕРВИСА
# ════════════════════════════════════════════════════════════

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           Часть 2 из 2 — Настройка сервиса              ║"
echo "╚══════════════════════════════════════════════════════════╝"
if ! $ADVANCED_SETUP; then
    echo "  (остальные параметры будут настроены автоматически)"
fi

# ── Блок 8: Администратор ─────────────────────────────────
if $ADVANCED_SETUP; then
    title "Блок 8 — Администратор"
fi
echo ""

ADMIN_USER=$(ask "Укажите логин администратора" "$(prev_val INSTALL_ADMIN_USER 'admin')")

if $MODIFY_MODE; then
    echo ""
    info "Пароль администратора: нажмите Enter чтобы оставить без изменений"
    ADMIN_PASS=$(ask_secret "Укажите новый пароль (или Enter чтобы пропустить)")
    if [ -n "$ADMIN_PASS" ]; then
        ADMIN_PASS2=$(ask_secret "Укажите пароль повторно")
        if [ "$ADMIN_PASS" != "$ADMIN_PASS2" ]; then
            warn "Пароли не совпадают — пароль не будет изменён"
            ADMIN_PASS=""
        elif [ ${#ADMIN_PASS} -lt 8 ]; then
            warn "Пароль слишком короткий — пароль не будет изменён"
            ADMIN_PASS=""
        else
            log "Пароль будет изменён"
        fi
    else
        log "Пароль без изменений"
    fi
else
    while true; do
        ADMIN_PASS=$(ask_secret "Укажите пароль администратора")
        if [ ${#ADMIN_PASS} -lt 8 ]; then
            warn "Минимум 8 символов"
            continue
        fi
        ADMIN_PASS2=$(ask_secret "Укажите пароль повторно")
        if [ "$ADMIN_PASS" = "$ADMIN_PASS2" ]; then
            log "Пароль установлен"
            break
        else
            warn "Пароли не совпадают"
        fi
    done
fi

# ── Блок 9: Регистрация пользователей ────────────────────
if $ADVANCED_SETUP; then
    title "Блок 9 — Регистрация пользователей"
fi
echo ""

OPEN_REGISTRATION=false
if $ADVANCED_SETUP; then
    _REG_DEFAULT="1"
    [ "$(prev_bool INSTALL_OPEN_REGISTRATION 'false')" = "y" ] && _REG_DEFAULT="2"

    echo "  [1] Только администратор создаёт аккаунты (рекомендуется)"
    echo "  [2] Открытая регистрация (любой может зарегистрироваться)"
    echo ""
    read -rp "$(echo -e "${BLUE}>>${NC} Выбор [${_REG_DEFAULT}]: ")" REG_MODE
    REG_MODE="${REG_MODE:-${_REG_DEFAULT}}"

    if [ "$REG_MODE" = "2" ]; then
        OPEN_REGISTRATION=true
        warn "Открытая регистрация — любой сможет создать аккаунт на вашем сервере"
        log "Регистрация: открытая"
    else
        log "Регистрация: только через администратора"
    fi
else
    log "Регистрация: только через администратора (рекомендуемый режим)"
fi

# ── Блок 10: Email уведомления ────────────────────────────
if $ADVANCED_SETUP; then
    title "Блок 10 — Email уведомления"
fi
echo ""

SMTP_ENABLED=false
SMTP_HOST=$(prev_val INSTALL_SMTP_HOST "")
SMTP_PORT=$(prev_val INSTALL_SMTP_PORT "")
SMTP_USER=$(prev_val INSTALL_SMTP_USER "")
SMTP_PASS=""
SMTP_FROM=$(prev_val INSTALL_SMTP_FROM "")

if $ADVANCED_SETUP; then
    _SMTP_DEFAULT=$(prev_bool INSTALL_SMTP_ENABLED "n")
    [ -n "$(prev_val INSTALL_SMTP_HOST '')" ] && _SMTP_DEFAULT="y"

    if ask_yn "Подтвердите настройку email уведомлений?" "$_SMTP_DEFAULT"; then
        SMTP_ENABLED=true
        echo ""
        # Определяем провайдер из сохранённого хоста
        _SMTP_PROV_DEFAULT="4"
        case "$(prev_val INSTALL_SMTP_HOST '')" in
            smtp.yandex.ru) _SMTP_PROV_DEFAULT="1" ;;
            smtp.mail.ru)   _SMTP_PROV_DEFAULT="2" ;;
            smtp.gmail.com) _SMTP_PROV_DEFAULT="3" ;;
        esac
        echo "  Выберите провайдер:"
        echo "  [1] Yandex 360"
        echo "  [2] Mail.ru"
        echo "  [3] Gmail"
        echo "  [4] Ввести вручную"
        echo ""
        read -rp "$(echo -e "${BLUE}>>${NC} Выбор [${_SMTP_PROV_DEFAULT}]: ")" SMTP_PROVIDER
        SMTP_PROVIDER="${SMTP_PROVIDER:-${_SMTP_PROV_DEFAULT}}"

        case "$SMTP_PROVIDER" in
            1)
                SMTP_HOST="smtp.yandex.ru"; SMTP_PORT="465"
                echo ""
                warn "Требуется пароль приложения (не основной пароль)"
                warn "Где взять: yandex.ru → Безопасность → Пароли приложений"
                echo ""
                SMTP_USER=$(ask "Укажите логин (ваш@yandex.ru)" "$SMTP_USER")
                SMTP_PASS=$(ask_secret "Укажите пароль приложения")
                SMTP_FROM="$SMTP_USER"
                ;;
            2)
                SMTP_HOST="smtp.mail.ru"; SMTP_PORT="465"
                echo ""
                warn "Требуется пароль приложения (не основной пароль)"
                warn "Где взять: mail.ru → Настройки → Безопасность → Пароли для внешних приложений"
                echo ""
                SMTP_USER=$(ask "Укажите логин (ваш@mail.ru)" "$SMTP_USER")
                SMTP_PASS=$(ask_secret "Укажите пароль приложения")
                SMTP_FROM="$SMTP_USER"
                ;;
            3)
                SMTP_HOST="smtp.gmail.com"; SMTP_PORT="587"
                echo ""
                warn "Требуется пароль приложения (не основной пароль)"
                warn "Где взять: myaccount.google.com → Безопасность → Пароли приложений"
                echo ""
                SMTP_USER=$(ask "Укажите логин (ваш@gmail.com)" "$SMTP_USER")
                SMTP_PASS=$(ask_secret "Укажите пароль приложения")
                SMTP_FROM="$SMTP_USER"
                ;;
            4)
                SMTP_HOST=$(ask "Укажите SMTP сервер" "$SMTP_HOST")
                SMTP_PORT=$(ask "Укажите SMTP порт" "${SMTP_PORT:-587}")
                SMTP_USER=$(ask "Укажите логин" "$SMTP_USER")
                SMTP_PASS=$(ask_secret "Укажите пароль")
                SMTP_FROM=$(ask "Укажите Email отправителя" "${SMTP_FROM:-$SMTP_USER}")
                ;;
        esac
        log "Email: настроен (${SMTP_HOST}:${SMTP_PORT})"
    else
        echo ""
        warn "Без email восстановление пароля возможно только через Synapse Admin UI."
        echo ""
        if ! ask_yn "Подтвердите продолжение без email уведомлений?" "y"; then
            SMTP_ENABLED=true
            warn "Вернитесь к настройке email"
        fi
    fi
else
    SMTP_ENABLED=false
    log "Email: отключен (рекомендуемый режим)"
fi

# ── Блок 11: Лимиты ──────────────────────────────────────
if $ADVANCED_SETUP; then
    title "Блок 11 — Лимиты"
fi
echo ""

if $ADVANCED_SETUP; then
    MAX_UPLOAD=$(ask "Укажите максимальный размер загружаемого файла" "$(prev_val INSTALL_MAX_UPLOAD '500M')")
else
    MAX_UPLOAD="500M"
    log "Макс. файл: ${MAX_UPLOAD} (рекомендуемый режим)"
fi

# ── Проверка соответствия ресурсов ────────────────────────
RESOURCE_WARN=false

if $USE_CALLS; then
    MIN_RAM_MB=5800; MIN_RAM_LABEL="6 GB (звонки включены)"
else
    MIN_RAM_MB=3800; MIN_RAM_LABEL="4 GB"
fi

[ "$RAM_MB" -lt "$MIN_RAM_MB" ]             && { warn "RAM: ${RAM_GB} GB — рекомендуется минимум ${MIN_RAM_LABEL}"; RESOURCE_WARN=true; }
[ "$CPU_CORES" -lt 2 ]                      && { warn "CPU: ${CPU_CORES} ядро — рекомендуется минимум 2"; RESOURCE_WARN=true; }
$USE_CALLS && [ "$CPU_CORES" -lt 3 ]        && { warn "CPU: ${CPU_CORES} ядра — со звонками рекомендуется минимум 3"; RESOURCE_WARN=true; }
[ "$DISK_FREE_GB" -lt 20 ]                  && { warn "Диск: ${DISK_FREE_GB} GB — рекомендуется минимум 20 GB"; RESOURCE_WARN=true; }

if $RESOURCE_WARN; then
    echo ""
    warn "Сервер не соответствует рекомендуемым требованиям."
    warn "Система может работать нестабильно."
    echo ""
    if ! ask_yn "Подтвердите продолжение установки (введите y — продолжить, n — отменить)" "n"; then
        warn "Установка отменена."
        exit 0
    fi
    echo ""
fi

# ── Блок 12: Подтверждение ────────────────────────────────
if $ADVANCED_SETUP; then
    title "Блок 12 — Подтверждение настроек"
else
    title "Подтверждение настроек"
fi
echo ""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║                  Итоговые настройки                     ║"
echo "╠══════════════════════════════════════════════════════════╣"
if $ADVANCED_SETUP; then
    printf "║  Режим:           %-39s ║\n" "ручной выбор параметров"
else
    printf "║  Режим:           %-39s ║\n" "установка с рекомендуемыми параметрами"
fi
printf "║  Домен сервера:   %-39s ║\n" "$DOMAIN"
printf "║  Домен пользователей: %-38s ║\n" "$SERVER_NAME"
printf "║  Пример логина:    %-39s ║\n" "@user:${SERVER_NAME}"
printf "║  Email SSL:       %-39s ║\n" "$EMAIL"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  Администратор:   %-39s ║\n" "$ADMIN_USER"
if $OPEN_REGISTRATION; then
    printf "║  Регистрация:     %-39s ║\n" "открытая"
else
    printf "║  Регистрация:     %-39s ║\n" "только через администратора"
fi
echo "╠══════════════════════════════════════════════════════════╣"
if $USE_B2B; then
    printf "║  Клиент:          %-39s ║\n" "B2B-связи"
else
    CLIENTS_DISPLAY=""
    $USE_ELEMENT    && CLIENTS_DISPLAY="${CLIENTS_DISPLAY}Element "
    $USE_CINNY      && CLIENTS_DISPLAY="${CLIENTS_DISPLAY}Cinny "
    $USE_FLUFFYCHAT && CLIENTS_DISPLAY="${CLIENTS_DISPLAY}FluffyChat"
    printf "║  Клиенты:         %-39s ║\n" "$CLIENTS_DISPLAY"
fi
if $USE_CALLS; then
    printf "║  Звонки:          %-39s ║\n" "включены"
else
    printf "║  Звонки:          %-39s ║\n" "отключены"
fi
if $USE_MINIO; then
    printf "║  Медиа S3:        %-39s ║\n" "MinIO"
else
    printf "║  Медиа S3:        %-39s ║\n" "отключено"
fi
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  Порт Element:    %-39s ║\n" ":${PORT}"
if $USE_MINIO; then
    [ -n "$MINIO_PORT" ] && printf "║  Порт MinIO:      %-39s ║\n" ":${MINIO_PORT}" || printf "║  Порт MinIO:      %-39s ║\n" "случайный"
fi
[ -n "$ADMIN_PORT" ]      && printf "║  Порт Admin:      %-39s ║\n" ":${ADMIN_PORT}" || printf "║  Порт Admin:      %-39s ║\n" "случайный"
$USE_CINNY      && { [ -n "$CINNY_PORT" ] && printf "║  Порт Cinny:      %-39s ║\n" ":${CINNY_PORT}" || printf "║  Порт Cinny:      %-39s ║\n" "случайный"; }
$USE_FLUFFYCHAT && { [ -n "$FLUFFYCHAT_PORT" ] && printf "║  Порт FluffyChat: %-39s ║\n" ":${FLUFFYCHAT_PORT}" || printf "║  Порт FluffyChat: %-39s ║\n" "случайный"; }
echo "╠══════════════════════════════════════════════════════════╣"
if $BACKUP_ENABLED; then
    $BACKUP_LOCAL && printf "║  Бэкап локально:  %-39s ║\n" "$BACKUP_DIR (${BACKUP_DAYS} дней)"
    $BACKUP_S3    && printf "║  Бэкап S3:        %-39s ║\n" "$S3_BUCKET (${S3_DAYS} дней)"
else
    printf "║  Бэкапы:          %-39s ║\n" "отключены"
fi
if $SMTP_ENABLED; then
    printf "║  Email:           %-39s ║\n" "${SMTP_HOST}:${SMTP_PORT}"
else
    printf "║  Email:           %-39s ║\n" "отключён"
fi
printf "║  Макс. файл:      %-39s ║\n" "$MAX_UPLOAD"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

_CONFIRM_LABEL="Начать установку"
$MODIFY_MODE && _CONFIRM_LABEL="Применить изменения"
[ -n "$REINSTALL_FLAG" ] && _CONFIRM_LABEL="Начать переустановку"

if ! ask_yn "${_CONFIRM_LABEL}?" "y"; then
    warn "Отменено. Запустите скрипт снова."
    exit 0
fi

# ════════════════════════════════════════════════════════════
# ЗАПУСК start.sh С ПАРАМЕТРАМИ
# ════════════════════════════════════════════════════════════
echo ""
info "Подготавливаем файлы установки..."

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
mkdir -p config/synapse config/nginx

BASE_URL="https://github.com/abc755g/b2bchatserver/releases/latest/download"

TMP_ARCHIVE=$(mktemp /tmp/b2b-archive.XXXXXX)
TMP_SUMS=$(mktemp /tmp/b2b-sums.XXXXXX)

if curl -fsSL "${BASE_URL}/b2b-chat.tar.gz" -o "$TMP_ARCHIVE" && \
   curl -fsSL "${BASE_URL}/SHA256SUMS" -o "$TMP_SUMS"; then
    # Проверяем целостность архива
    EXPECTED_SUM=$(grep 'b2b-chat.tar.gz' "$TMP_SUMS" | awk '{print $1}')
    ACTUAL_SUM=$(sha256sum "$TMP_ARCHIVE" | awk '{print $1}')
    if [ "$EXPECTED_SUM" != "$ACTUAL_SUM" ]; then
        rm -f "$TMP_ARCHIVE" "$TMP_SUMS"
        err "Проверка целостности архива не прошла — файл повреждён или подменён."
    fi
    rm -f "$TMP_SUMS"
    tar xzf "$TMP_ARCHIVE" -C .
    rm -f "$TMP_ARCHIVE"
    log "Файлы скачаны из GitHub"
else
    rm -f "$TMP_ARCHIVE"
    warn "Не удалось скачать архив из GitHub Releases, используем локальные файлы..."

    if [ -f "${SOURCE_DIR}/start.sh" ] && [ -f "${SOURCE_DIR}/manage.sh" ] && \
       [ -f "${SOURCE_DIR}/config/synapse/log.config" ] && [ -f "${SOURCE_DIR}/config/nginx/matrix-http.conf" ]; then
        if [ "${SOURCE_DIR}" != "${INSTALL_DIR}" ]; then
            cp -f "${SOURCE_DIR}/start.sh" ./start.sh
            cp -f "${SOURCE_DIR}/manage.sh" ./manage.sh
            cp -f "${SOURCE_DIR}/config/synapse/log.config" ./config/synapse/log.config
            cp -f "${SOURCE_DIR}/config/nginx/matrix-http.conf" ./config/nginx/matrix-http.conf
        fi
        log "Используем локальные файлы установки"
    else
        err "Не удалось скачать архив из GitHub, и локальные файлы установки не найдены."
    fi
fi

chmod +x start.sh manage.sh

# Формируем параметры для start.sh
PARAMS="--domain ${DOMAIN} --server-name ${SERVER_NAME} --email ${EMAIL}"
PARAMS="${PARAMS} --admin-user ${ADMIN_USER}"
PARAMS="${PARAMS} --port ${PORT}"
$USE_MINIO               && PARAMS="${PARAMS} --minio"
$USE_MINIO && [ -n "$MINIO_PORT" ] && PARAMS="${PARAMS} --minio-port ${MINIO_PORT}"
[ -n "$ADMIN_PORT" ]      && PARAMS="${PARAMS} --admin-port ${ADMIN_PORT}"
PARAMS="${PARAMS} --max-upload ${MAX_UPLOAD}"

if ! $USE_B2B; then
    $USE_ELEMENT    && PARAMS="${PARAMS} --client element"
    $USE_CINNY      && PARAMS="${PARAMS} --client cinny"
    $USE_CINNY      && [ -n "$CINNY_PORT" ] && PARAMS="${PARAMS} --cinny-port ${CINNY_PORT}"
    $USE_FLUFFYCHAT && PARAMS="${PARAMS} --client fluffychat"
    $USE_FLUFFYCHAT && [ -n "$FLUFFYCHAT_PORT" ] && PARAMS="${PARAMS} --fluffychat-port ${FLUFFYCHAT_PORT}"
fi

$USE_CALLS         && PARAMS="${PARAMS} --calls"
$OPEN_REGISTRATION && PARAMS="${PARAMS} --open-registration"

if $SMTP_ENABLED && [ -n "$SMTP_PASS" ]; then
    PARAMS="${PARAMS} --smtp-host ${SMTP_HOST} --smtp-port ${SMTP_PORT}"
    PARAMS="${PARAMS} --smtp-user ${SMTP_USER}"
    PARAMS="${PARAMS} --smtp-from ${SMTP_FROM}"
fi

if $BACKUP_ENABLED; then
    $BACKUP_LOCAL && PARAMS="${PARAMS} --backup-local ${BACKUP_DIR} --backup-days ${BACKUP_DAYS}"
    $BACKUP_S3    && PARAMS="${PARAMS} --backup-s3 --s3-endpoint ${S3_ENDPOINT} --s3-bucket ${S3_BUCKET}"
    $BACKUP_S3    && PARAMS="${PARAMS} --s3-days ${S3_DAYS}"
    $BACKUP_MEDIA && PARAMS="${PARAMS} --backup-media"
    PARAMS="${PARAMS} --backup-schedule ${BACKUP_SCHEDULE}"
fi

[ -n "$REINSTALL_FLAG" ] && PARAMS="${PARAMS} ${REINSTALL_FLAG}"

info "Запускаем установку..."
echo ""
SECRETS_FILE=$(mktemp /tmp/b2b-chat-secrets.XXXXXX)
chmod 600 "$SECRETS_FILE"
trap 'rm -f "$SECRETS_FILE"' EXIT
# Используем printf чтобы спецсимволы в паролях ($, `, \) не интерпретировались
{
    printf 'ADMIN_PASS=%s\n'    "$ADMIN_PASS"
    printf 'SMTP_PASS=%s\n'     "$SMTP_PASS"
    printf 'S3_ACCESS_KEY=%s\n' "$S3_ACCESS_KEY"
    printf 'S3_SECRET_KEY=%s\n' "$S3_SECRET_KEY"
} > "$SECRETS_FILE"

INSTALL_FROM_INSTALL_SH=true bash start.sh $PARAMS --env-file "$SECRETS_FILE"
rm -f "$SECRETS_FILE"
trap - EXIT

# ── Шпаргалка по управлению ───────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Управление сервером                        ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  ./manage.sh start              Запустить стек          ║"
echo "║  ./manage.sh stop               Остановить (данные OK)  ║"
echo "║  ./manage.sh restart            Перезапустить           ║"
echo "║  ./manage.sh status             Статус контейнеров      ║"
echo "║  ./manage.sh health             Здоровье системы        ║"
echo "║  ./manage.sh logs               Логи всех сервисов      ║"
echo "║  ./manage.sh update             Обновить образы         ║"
echo "║  ./manage.sh backup             Бэкап прямо сейчас      ║"
echo "║  ./manage.sh registration       Регистрация вкл/выкл    ║"
echo "║  ./manage.sh federation         Управление федерацией   ║"
echo "║  ./manage.sh password-reset     Экстренный сброс пароля ║"
echo "║  ./manage.sh ssl-renew          Обновить SSL вручную    ║"
echo "║  ./manage.sh media-clean        Очистить кэш медиа      ║"
echo "║  ./manage.sh info               Адреса, статус, порты   ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  ./install.sh                   Изменить настройки      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
