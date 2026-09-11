#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log()   { echo -e "${GREEN}[OK]${NC} $*"; }
info()  { echo -e "${BLUE}[..]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!!]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

INSTALL_DIR="/opt/b2b-chat"

# ── Проверка установки ────────────────────────────────────
[ ! -f "${INSTALL_DIR}/.env" ] && err "B2B-чат не установлен. Запустите install.sh"
cd "$INSTALL_DIR"

HOMESERVER_YAML="./config/synapse/homeserver.yaml"

# ── Хелпер: читать/писать homeserver.yaml ────────────────
hs_get() {
    grep "^${1}:" "$HOMESERVER_YAML" 2>/dev/null | awk '{print $2}' || echo ""
}

hs_set() {
    local key="$1" val="$2"
    if grep -q "^${key}:" "$HOMESERVER_YAML" 2>/dev/null; then
        sed -i "s|^${key}:.*|${key}: ${val}|" "$HOMESERVER_YAML"
    else
        echo "${key}: ${val}" >> "$HOMESERVER_YAML"
    fi
}

hs_remove_block() {
    # Удаляет блок начиная с ключа до следующей пустой строки или не-отступной строки
    local key="$1"
    sed -i "/^${key}:/,/^[^ #]/{/^${key}:/d; /^  - /d; /^[^ #]/!d}" "$HOMESERVER_YAML" 2>/dev/null || true
    sed -i "/^${key}:/d" "$HOMESERVER_YAML" 2>/dev/null || true
}

# ── Хелперы: федерация ────────────────────────────────────
fed_mode() {
    # open — блока нет; closed — пустой список; whitelist — есть домены
    if ! grep -q "^federation_domain_whitelist:" "$HOMESERVER_YAML" 2>/dev/null; then
        echo "open"
    elif [ -z "$(fed_list)" ]; then
        echo "closed"
    else
        echo "whitelist"
    fi
}

fed_list() {
    grep -A 200 "^federation_domain_whitelist:" "$HOMESERVER_YAML" 2>/dev/null \
        | sed '1d' | sed '/^[^ ]/q' | grep "^  - " | awk '{print $2}' || true
}

fed_write() {
    # $@ — домены; пустой список = закрытая федерация
    python3 - "$HOMESERVER_YAML" "$@" <<'PYEOF'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1]); domains = sys.argv[2:]
text = path.read_text()
text = re.sub(r"(?m)^federation_domain_whitelist:.*\n(?:  - .*\n)*", "", text)
block = ("federation_domain_whitelist:\n" + "".join(f"  - {d}\n" for d in domains)) if domains \
    else "federation_domain_whitelist: []\n"
path.write_text(text.rstrip("\n") + "\n\n" + block)
PYEOF
    hs_set "allow_public_rooms_over_federation" "false"
}

fed_open() {
    python3 - "$HOMESERVER_YAML" <<'PYEOF'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
path.write_text(re.sub(r"(?m)^federation_domain_whitelist:.*\n(?:  - .*\n)*", "", path.read_text()))
PYEOF
    hs_set "allow_public_rooms_over_federation" "true"
}

fed_restart() {
    # Whitelist читается только при старте Synapse — без рестарта правка не действует
    info "Перезапускаем Synapse, чтобы применить список федерации..."
    docker compose restart synapse >/dev/null
    log "Synapse перезапущен"
}

fed_valid_domain() {
    [[ "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:[0-9]+)?$ ]]
}

# ── Хелперы: MAS ──────────────────────────────────────────
mas_enabled() {
    [ "$(grep "^INSTALL_USE_MAS=" .env | cut -d= -f2)" = "true" ]
}

mas_cli() {
    docker compose exec -T mas mas-cli -c /config/config.yaml "$@"
}

# ── Справка ───────────────────────────────────────────────
usage() {
    echo ""
    echo "Использование: manage.sh <команда> [опции]"
    echo ""
    echo "Команды:"
    echo "  start              Запустить стек"
    echo "  stop               Остановить стек (данные не удаляются)"
    echo "  restart            Перезапустить стек"
    echo "  restart --service  Перезапустить один сервис (напр: --service nginx)"
    echo "  status             Статус всех контейнеров"
    echo "  health             Проверка работоспособности"
    echo "  logs               Логи всех сервисов"
    echo "  logs --service     Логи конкретного сервиса (напр: --service synapse)"
    echo "  update             Обновить образы и перезапустить"
    echo "  backup             Запустить бэкап прямо сейчас"
    echo "  registration       Управление регистрацией пользователей"
    echo "  federation         Управление федерацией (без опций — меню)"
    echo "    --list                    Показать режим и список серверов"
    echo "    --add DOMAIN              Добавить сервер в whitelist"
    echo "    --remove DOMAIN           Убрать сервер из whitelist"
    echo "    --sync-from URL           Загрузить список серверов по URL"
    echo "    --mode open|closed|whitelist  Сменить режим"
    echo "    --test DOMAIN             Проверить связность с сервером"
    echo "  verify-domain --token T   Опубликовать токен подтверждения домена"
    echo "  backup-key [--out PATH]   Сохранить ключ подписи сервера"
    echo "  admin-token               Выдать токен администратора для Admin UI"
    echo "  oidc --issuer URL --client-id ID [--name NAME]"
    echo "                            Вход через внешнего OIDC-провайдера (нужен MAS)"
    echo "  oidc --disable            Отключить внешний вход"
    echo "  mas <команда...>          Прямой вызов mas-cli manage (set-password и др.)"
    echo "  mas-migrate [--apply]     Перенос аккаунтов Synapse в MAS (syn2mas)"
    echo "  password-reset     Экстренный сброс пароля администратора"
    echo "  ssl-renew          Принудительное обновление SSL-сертификата"
    echo "  media-clean        Очистить кэш медиафайлов (освободить место)"
    echo "  wipe               Полная очистка установки (контейнеры, тома, конфиг)"
    echo "  info               Показать адреса, статус и порты"
    echo ""
}

# ── Парсинг аргументов ────────────────────────────────────
COMMAND="${1:-}"
SERVICE=""
FED_LIST=false; FED_ADD=""; FED_REMOVE=""; FED_SYNC=""; FED_MODE=""; FED_TEST=""
TOKEN=""; OUT=""; OIDC_ISSUER=""; OIDC_CLIENT_ID=""; OIDC_NAME=""; OIDC_DISABLE=false; APPLY=false
shift || true

# mas — прозрачная прокладка к mas-cli, свои аргументы не разбираем
if [ "$COMMAND" = "mas" ]; then
    MAS_ARGS=("$@")
    set --
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --service)   SERVICE="$2";        shift 2 ;;
        --list)      FED_LIST=true;       shift ;;
        --add)       FED_ADD="$2";        shift 2 ;;
        --remove)    FED_REMOVE="$2";     shift 2 ;;
        --sync-from) FED_SYNC="$2";       shift 2 ;;
        --mode)      FED_MODE="$2";       shift 2 ;;
        --test)      FED_TEST="$2";       shift 2 ;;
        --token)     TOKEN="$2";          shift 2 ;;
        --out)       OUT="$2";            shift 2 ;;
        --issuer)    OIDC_ISSUER="$2";    shift 2 ;;
        --client-id) OIDC_CLIENT_ID="$2"; shift 2 ;;
        --name)      OIDC_NAME="$2";      shift 2 ;;
        --disable)   OIDC_DISABLE=true;   shift ;;
        --apply)     APPLY=true;          shift ;;
        --help|-h) usage; exit 0 ;;
        *) err "Неизвестный параметр: $1" ;;
    esac
done

[ -z "$COMMAND" ] && { usage; exit 0; }

# ── Команды ───────────────────────────────────────────────
case "$COMMAND" in

    start)
        info "Запускаем B2B-чат..."
        docker compose up -d
        log "Стек запущен"
        ;;

    stop)
        info "Останавливаем B2B-чат..."
        docker compose stop
        log "Стек остановлен (данные и база данных сохранены)"
        info "Для запуска: ./manage.sh start"
        ;;

    restart)
        if [ -n "$SERVICE" ]; then
            info "Перезапускаем сервис: ${SERVICE}..."
            docker compose restart "$SERVICE"
            log "Сервис ${SERVICE} перезапущен"
        else
            info "Перезапускаем B2B-чат..."
            docker compose restart
            log "Стек перезапущен"
        fi
        ;;

    status)
        echo ""
        docker compose ps
        echo ""
        ;;

    logs)
        if [ -n "$SERVICE" ]; then
            docker compose logs -f --tail=100 "$SERVICE"
        else
            docker compose logs -f --tail=50
        fi
        ;;

    update)
        info "Обновляем образы..."
        echo ""
        warn "Перед обновлением рекомендуется сделать бэкап: ./manage.sh backup"
        echo ""
        # Synapse собирается локально — его образа в реестре нет, pull его пропускает
        docker compose pull --ignore-buildable 2>/dev/null || docker compose pull || true
        # Версии образов запинены в start.sh: pull подтянет только пересобранные
        # теги. Смена версии — перезапуск start.sh новой ревизии.
        docker compose build --pull 2>/dev/null || true
        info "Перезапускаем сервисы с новыми образами..."
        docker compose up -d --remove-orphans
        info "Удаляем старые образы..."
        docker image prune -f 2>/dev/null || true
        log "Обновление завершено"
        echo ""
        warn "Проверьте работоспособность: ./manage.sh health"
        warn "При мажорном обновлении Synapse — сверьтесь с changelog: https://github.com/element-hq/synapse/releases"
        warn "При мажорном обновлении LiveKit — проверьте совместимость livekit.yaml: https://github.com/livekit/livekit/releases"
        echo ""
        ;;

    backup)
        if [ ! -f "${INSTALL_DIR}/backup.sh" ]; then
            err "Бэкап не настроен. Запустите install.sh и включите бэкапы."
        fi
        info "Запускаем бэкап..."
        bash "${INSTALL_DIR}/backup.sh"
        ;;

    info)
        DOMAIN=$(grep "^SYNAPSE_DOMAIN=" .env | cut -d= -f2)
        SERVER_NAME=$(grep "^SERVER_NAME=" .env | cut -d= -f2)
        MINIO_PORT=$(grep "^INSTALL_MINIO_PORT=" .env | cut -d= -f2)
        ADMIN_PORT=$(grep "^INSTALL_ADMIN_PORT=" .env | cut -d= -f2)
        CINNY_PORT=$(grep "^INSTALL_CINNY_PORT=" .env | cut -d= -f2)
        FLUFFYCHAT_PORT=$(grep "^INSTALL_FLUFFYCHAT_PORT=" .env | cut -d= -f2)
        USE_ELEMENT=$(grep "^INSTALL_USE_ELEMENT=" .env | cut -d= -f2)
        USE_CINNY=$(grep "^INSTALL_USE_CINNY=" .env | cut -d= -f2)
        USE_FLUFFYCHAT=$(grep "^INSTALL_USE_FLUFFYCHAT=" .env | cut -d= -f2)
        USE_MINIO=$(grep "^INSTALL_USE_MINIO=" .env | cut -d= -f2)
        USE_CALLS=$(grep "^INSTALL_USE_CALLS=" .env | cut -d= -f2)
        ADMIN_USER=$(grep "^INSTALL_ADMIN_USER=" .env | cut -d= -f2)

        # Читаем из homeserver.yaml
        REG_MODE="закрытая"
        if [ -f "$HOMESERVER_YAML" ]; then
            _REG=$(hs_get "enable_registration")
            [ "$_REG" = "true" ] && REG_MODE="открытая"
        fi

        FED_MODE="открытая"
        if [ -f "$HOMESERVER_YAML" ] && grep -q "^federation_domain_whitelist:" "$HOMESERVER_YAML" 2>/dev/null; then
            _WL=$(grep -A 5 "^federation_domain_whitelist:" "$HOMESERVER_YAML" | grep "^  - " | head -1)
            [ -z "$_WL" ] && FED_MODE="закрытая" || FED_MODE="whitelist"
        fi

        BACKUP_STATUS="не настроен"
        [ -f "${INSTALL_DIR}/backup.sh" ] && BACKUP_STATUS="настроен"
        [ -f /etc/cron.d/matrix-backup ] && BACKUP_STATUS="${BACKUP_STATUS}, автозапуск активен"

        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║                  B2B-чат — информация                   ║"
        echo "╠══════════════════════════════════════════════════════════╣"
        printf "║  Synapse:    https://%-36s ║\n" "${DOMAIN}"
        [ "$USE_ELEMENT" = "true" ] && printf "║  Element:    https://%-36s ║\n" "${DOMAIN}"
        [ "$USE_CINNY" = "true" ]   && printf "║  Cinny:      https://${DOMAIN}:%-$((36 - ${#DOMAIN}))s ║\n" "${CINNY_PORT}"
        [ "$USE_FLUFFYCHAT" = "true" ] && printf "║  FluffyChat: https://${DOMAIN}:%-$((36 - ${#DOMAIN}))s ║\n" "${FLUFFYCHAT_PORT}"
        [ "$USE_MINIO" = "true" ] && printf "║  MinIO:      https://${DOMAIN}:%-$((36 - ${#DOMAIN}))s ║\n" "${MINIO_PORT}"
        printf "║  Admin UI:   https://${DOMAIN}:%-$((36 - ${#DOMAIN}))s ║\n" "${ADMIN_PORT}"
        [ "$USE_CALLS" = "true" ] && printf "║  STUN/TURN:  %-44s ║\n" "${DOMAIN}:3478"
        echo "╠══════════════════════════════════════════════════════════╣"
        printf "║  Администратор:  @%-39s ║\n" "${ADMIN_USER}:${SERVER_NAME}"
        printf "║  Регистрация:    %-40s ║\n" "$REG_MODE"
        printf "║  Аутентификация: %-40s ║\n" "$(mas_enabled && echo 'MAS' || echo 'встроенная в Synapse')"
        printf "║  Федерация:      %-40s ║\n" "$FED_MODE"
        printf "║  Бэкап:          %-40s ║\n" "$BACKUP_STATUS"
        echo "╠══════════════════════════════════════════════════════════╣"
        echo "║  Управление:     ./manage.sh --help                     ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        ;;

    health)
        DOMAIN=$(grep "^SYNAPSE_DOMAIN=" .env | cut -d= -f2)
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║               B2B-чат — проверка состояния              ║"
        echo "╠══════════════════════════════════════════════════════════╣"

        # Контейнеры
        ALL_OK=true
        while IFS= read -r line; do
            NAME=$(echo "$line" | awk '{print $1}')
            STATE=$(echo "$line" | awk '{print $2}')
            if echo "$STATE" | grep -qi "up\|running"; then
                printf "║  %-20s %-35s ║\n" "$NAME" "$(echo -e "${GREEN}running${NC}")"
            else
                printf "║  %-20s %-35s ║\n" "$NAME" "$(echo -e "${RED}${STATE}${NC}")"
                ALL_OK=false
            fi
        done < <(docker compose ps --format "table {{.Name}}\t{{.State}}" 2>/dev/null | tail -n +2)

        echo "╠══════════════════════════════════════════════════════════╣"

        # Synapse HTTP
        if curl -sf --max-time 5 "https://${DOMAIN}/_matrix/client/versions" >/dev/null 2>&1; then
            printf "║  %-20s %-35s ║\n" "Synapse API" "$(echo -e "${GREEN}отвечает${NC}")"
        else
            printf "║  %-20s %-35s ║\n" "Synapse API" "$(echo -e "${RED}не отвечает${NC}")"
            ALL_OK=false
        fi

        # Федерация — ключи сервера по адресу из well-known (или :8448)
        _FT=$(curl -sf --max-time 5 "https://${DOMAIN}/.well-known/matrix/server" 2>/dev/null \
            | grep -o '"m.server"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:[[:space:]]*"\(.*\)"/\1/' || true)
        [ -z "$_FT" ] && _FT="${DOMAIN}:8448"
        if curl -sf --max-time 5 "https://${_FT}/_matrix/key/v2/server" 2>/dev/null | grep -q '"server_name"'; then
            printf "║  %-20s %-35s ║\n" "Федерация" "$(echo -e "${GREEN}отвечает (${_FT})${NC}")"
        else
            printf "║  %-20s %-35s ║\n" "Федерация" "$(echo -e "${YELLOW}не отвечает (${_FT})${NC}")"
        fi

        # MAS
        if mas_enabled; then
            if mas_cli doctor >/dev/null 2>&1; then
                printf "║  %-20s %-35s ║\n" "MAS" "$(echo -e "${GREEN}отвечает${NC}")"
            else
                printf "║  %-20s %-35s ║\n" "MAS" "$(echo -e "${RED}doctor: ошибки${NC}")"
                ALL_OK=false
            fi
        fi

        # SSL сертификат
        CERT_EXPIRY=$(echo | openssl s_client -servername "$DOMAIN" -connect "${DOMAIN}:443" 2>/dev/null \
            | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
        if [ -n "$CERT_EXPIRY" ]; then
            EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$CERT_EXPIRY" +%s 2>/dev/null || echo 0)
            NOW_EPOCH=$(date +%s)
            DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
            if [ "$DAYS_LEFT" -gt 14 ]; then
                printf "║  %-20s %-35s ║\n" "SSL сертификат" "$(echo -e "${GREEN}${DAYS_LEFT} дней${NC}")"
            else
                printf "║  %-20s %-35s ║\n" "SSL сертификат" "$(echo -e "${RED}истекает через ${DAYS_LEFT} дней!${NC}")"
                ALL_OK=false
            fi
        else
            printf "║  %-20s %-35s ║\n" "SSL сертификат" "$(echo -e "${YELLOW}не проверить${NC}")"
        fi

        echo "╠══════════════════════════════════════════════════════════╣"

        # Диск
        DISK_USED=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
        DISK_INFO=$(df -h / | awk 'NR==2{print $3 " / " $2 " (" $5 " использовано)"}')
        if [ "$DISK_USED" -lt 80 ]; then
            printf "║  %-20s %-35s ║\n" "Диск" "$(echo -e "${GREEN}${DISK_INFO}${NC}")"
        elif [ "$DISK_USED" -lt 90 ]; then
            printf "║  %-20s %-35s ║\n" "Диск" "$(echo -e "${YELLOW}${DISK_INFO}${NC}")"
            ALL_OK=false
        else
            printf "║  %-20s %-35s ║\n" "Диск" "$(echo -e "${RED}${DISK_INFO}${NC}")"
            ALL_OK=false
        fi

        # RAM
        RAM_USED=$(free -m | awk '/^Mem:/{printf "%.0f", $3/$2*100}')
        RAM_INFO=$(free -h | awk '/^Mem:/{print $3 " / " $2}')
        if [ "$RAM_USED" -lt 80 ]; then
            printf "║  %-20s %-35s ║\n" "RAM" "$(echo -e "${GREEN}${RAM_INFO} (${RAM_USED}%)${NC}")"
        elif [ "$RAM_USED" -lt 90 ]; then
            printf "║  %-20s %-35s ║\n" "RAM" "$(echo -e "${YELLOW}${RAM_INFO} (${RAM_USED}%)${NC}")"
        else
            printf "║  %-20s %-35s ║\n" "RAM" "$(echo -e "${RED}${RAM_INFO} (${RAM_USED}%)${NC}")"
            ALL_OK=false
        fi

        echo "╠══════════════════════════════════════════════════════════╣"
        if $ALL_OK; then
            echo "║  $(echo -e "${GREEN}Всё в порядке${NC}")                                         ║"
        else
            echo "║  $(echo -e "${RED}Обнаружены проблемы — проверьте выше${NC}")                  ║"
        fi
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        ;;

    registration)
        [ ! -f "$HOMESERVER_YAML" ] && err "homeserver.yaml не найден"

        CURRENT=$(hs_get "enable_registration")
        echo ""
        if [ "$CURRENT" = "true" ]; then
            warn "Регистрация сейчас: ОТКРЫТАЯ — любой может создать аккаунт"
        else
            log "Регистрация сейчас: ЗАКРЫТАЯ — только администратор создаёт аккаунты"
        fi
        echo ""
        echo "  [1] Закрытая — только администратор создаёт аккаунты"
        echo "  [2] Открытая — любой может зарегистрироваться"
        echo "  [3] Отмена"
        echo ""
        read -rp "$(echo -e "${BLUE}>>${NC} Выбор [1]: ")" _REG_CHOICE
        _REG_CHOICE="${_REG_CHOICE:-1}"

        # С MAS переключатель живёт в его конфиге; enable_registration в Synapse
        # остаётся false и служит только меткой для info/registration
        _apply_registration() {
            hs_set "enable_registration" "$1"
            if mas_enabled; then
                sed -i "s|^  password_registration_enabled: .*|  password_registration_enabled: $1|" ./config/mas/config.yaml
                info "Перезапускаем MAS..."
                docker compose restart mas >/dev/null
            else
                info "Перезапускаем Synapse..."
                docker compose restart synapse >/dev/null
            fi
        }

        case "$_REG_CHOICE" in
            1)
                _apply_registration false
                log "Регистрация закрыта"
                ;;
            2)
                warn "Любой сможет создать аккаунт на вашем сервере!"
                read -rp "$(echo -e "${YELLOW}?${NC} Подтвердить? [y/N]: ")" _CONFIRM
                if [[ "$_CONFIRM" =~ ^[Yy]$ ]]; then
                    _apply_registration true
                    log "Регистрация открыта"
                else
                    warn "Отменено"
                fi
                ;;
            *) warn "Отменено" ;;
        esac
        echo ""
        ;;

    federation)
        [ ! -f "$HOMESERVER_YAML" ] && err "homeserver.yaml не найден"
        DOMAIN=$(grep "^SYNAPSE_DOMAIN=" .env | cut -d= -f2)

        # ── Неинтерактивные операции ──
        if $FED_LIST; then
            echo ""
            case "$(fed_mode)" in
                open)      log  "Федерация: ОТКРЫТАЯ — общение со всем Matrix-миром" ;;
                closed)    warn "Федерация: ЗАКРЫТАЯ — изолированный контур" ;;
                whitelist) log  "Федерация: WHITELIST — только разрешённые серверы:"
                           fed_list | sed 's/^/    /' ;;
            esac
            echo ""
            exit 0
        fi

        if [ -n "$FED_ADD" ]; then
            fed_valid_domain "$FED_ADD" || err "Некорректный домен: ${FED_ADD}"
            mapfile -t _CUR < <(fed_list)
            for d in "${_CUR[@]}"; do [ "$d" = "$FED_ADD" ] && { log "Уже в списке: ${FED_ADD}"; exit 0; }; done
            [ "$(fed_mode)" = "open" ] && warn "Федерация была открытой — переключаю в режим whitelist"
            fed_write "${_CUR[@]}" "$FED_ADD"
            log "Добавлен: ${FED_ADD}"
            fed_restart
            exit 0
        fi

        if [ -n "$FED_REMOVE" ]; then
            mapfile -t _CUR < <(fed_list)
            _NEW=()
            _FOUND=false
            for d in "${_CUR[@]}"; do
                [ "$d" = "$FED_REMOVE" ] && { _FOUND=true; continue; }
                _NEW+=("$d")
            done
            $_FOUND || err "Нет в списке: ${FED_REMOVE}"
            fed_write "${_NEW[@]}"
            log "Удалён: ${FED_REMOVE}"
            [ ${#_NEW[@]} -eq 0 ] && warn "Список пуст — федерация теперь ЗАКРЫТА"
            fed_restart
            exit 0
        fi

        if [ -n "$FED_SYNC" ]; then
            # Формат ответа: JSON-массив строк, объект {"domains":[...]} или домены построчно.
            # Откуда список — дело администратора; скрипт ничего не знает об источнике.
            info "Загружаем список серверов: ${FED_SYNC}"
            _BODY=$(curl -sfL --max-time 20 "$FED_SYNC") || err "Не удалось загрузить ${FED_SYNC}"
            mapfile -t _NEW < <(printf '%s' "$_BODY" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
    if isinstance(data, dict):
        data = data.get("domains") or data.get("servers") or []
    items = [str(x) for x in data]
except ValueError:
    items = raw.split()
for d in items:
    d = d.strip().lower()
    if d:
        print(d)
')
            [ ${#_NEW[@]} -eq 0 ] && err "Список пуст или не разобран — whitelist не тронут"
            for d in "${_NEW[@]}"; do fed_valid_domain "$d" || err "Некорректный домен в списке: ${d}"; done
            mapfile -t _CUR < <(fed_list)
            _ADDED=(); _REMOVED=()
            for d in "${_NEW[@]}"; do printf '%s\n' "${_CUR[@]}" | grep -qx "$d" || _ADDED+=("$d"); done
            for d in "${_CUR[@]}"; do printf '%s\n' "${_NEW[@]}" | grep -qx "$d" || _REMOVED+=("$d"); done
            if [ ${#_ADDED[@]} -eq 0 ] && [ ${#_REMOVED[@]} -eq 0 ] && [ "$(fed_mode)" = "whitelist" ]; then
                log "Список не изменился (${#_NEW[@]} серверов)"
                exit 0
            fi
            fed_write "${_NEW[@]}"
            [ ${#_ADDED[@]} -gt 0 ]   && log  "Добавлены: ${_ADDED[*]}"
            [ ${#_REMOVED[@]} -gt 0 ] && warn "Убраны: ${_REMOVED[*]}"
            fed_restart
            exit 0
        fi

        if [ -n "$FED_MODE" ]; then
            case "$FED_MODE" in
                open)      fed_open; log "Федерация открыта" ;;
                closed)    fed_write; log "Федерация закрыта — изолированный контур" ;;
                whitelist) mapfile -t _CUR < <(fed_list); fed_write "${_CUR[@]}"
                           log "Режим whitelist (${#_CUR[@]} серверов)" ;;
                *) err "Режим: open | closed | whitelist" ;;
            esac
            fed_restart
            exit 0
        fi

        if [ -n "$FED_TEST" ]; then
            _T="$FED_TEST"
            echo ""
            info "Проверяем федерацию с ${_T}"

            # 1. Нас пускают?
            case "$(fed_mode)" in
                open) log "Наш режим: открытая федерация" ;;
                closed) warn "Наш режим: ЗАКРЫТАЯ федерация — ${_T} не сможет с нами общаться" ;;
                whitelist)
                    if fed_list | grep -qx "$_T"; then log "${_T} есть в нашем whitelist"
                    else warn "${_T} НЕТ в нашем whitelist: ./manage.sh federation --add ${_T}"; fi ;;
            esac

            # 2. Делегация: куда на самом деле ходить
            _WK=$(curl -sf --max-time 10 "https://${_T}/.well-known/matrix/server" 2>/dev/null || true)
            _TARGET=$(printf '%s' "$_WK" | grep -o '"m.server"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:[[:space:]]*"\(.*\)"/\1/')
            if [ -n "$_TARGET" ]; then
                log "well-known: ${_T} → ${_TARGET}"
            else
                _TARGET="${_T}:8448"
                warn "well-known не отдан, пробуем ${_TARGET}"
            fi

            # 3. Ключи сервера — базовый эндпоинт федерации
            _KEYS=$(curl -sf --max-time 10 "https://${_TARGET}/_matrix/key/v2/server" 2>/dev/null || true)
            if printf '%s' "$_KEYS" | grep -q '"server_name"'; then
                _SN=$(printf '%s' "$_KEYS" | grep -o '"server_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
                log "Федерационный API отвечает, server_name: ${_SN}"
                [ "$_SN" != "$_T" ] && warn "server_name (${_SN}) не совпадает с доменом (${_T}) — проверьте делегацию у партнёра"
            else
                warn "https://${_TARGET}/_matrix/key/v2/server не отвечает: порт закрыт, TLS невалиден или сервер выключен"
            fi

            # 4. Видны ли мы снаружи — тот же тест в свою сторону
            _SELF_NAME=$(grep "^SERVER_NAME=" .env | cut -d= -f2)
            _SELF_WK=$(curl -sf --max-time 10 "https://${_SELF_NAME}/.well-known/matrix/server" 2>/dev/null || true)
            _SELF_TARGET=$(printf '%s' "$_SELF_WK" | grep -o '"m.server"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:[[:space:]]*"\(.*\)"/\1/')
            [ -z "$_SELF_TARGET" ] && _SELF_TARGET="${_SELF_NAME}:8448"
            if curl -sf --max-time 10 "https://${_SELF_TARGET}/_matrix/key/v2/server" 2>/dev/null | grep -q '"server_name"'; then
                log "Наш сервер виден снаружи: https://${_SELF_TARGET}"
            else
                warn "Наш сервер не отвечает по https://${_SELF_TARGET} — партнёр не сможет к нам достучаться"
            fi

            echo ""
            info "Партнёру: добавить ${_SELF_NAME} в свой whitelist и прогнать такой же тест в свою сторону"
            echo ""
            exit 0
        fi

        # ── Интерактивное меню ──
        CURRENT_MODE=$(fed_mode)
        echo ""
        case "$CURRENT_MODE" in
            open)      log  "Федерация сейчас: ОТКРЫТАЯ — общение со всем Matrix-миром" ;;
            closed)    warn "Федерация сейчас: ЗАКРЫТАЯ — изолированный контур" ;;
            whitelist) log  "Федерация сейчас: WHITELIST — только разрешённые серверы:"
                       fed_list | sed 's/^/    /' ;;
        esac

        echo ""
        echo "  [1] Whitelist   — только указанные серверы (рекомендуется)"
        echo "  [2] Закрытая    — изолированный контур, нет общения с внешними серверами"
        echo "  [3] Открытая    — общение со всем Matrix-миром"
        echo "  [4] Отмена"
        echo ""
        read -rp "$(echo -e "${BLUE}>>${NC} Выбор: ")" _FED_CHOICE

        case "$_FED_CHOICE" in
            1)
                echo ""
                echo "  Введите домены серверов через Enter. Пустая строка — завершить."
                echo "  Текущий список будет заменён. Добавить один сервер без меню:"
                echo "    ./manage.sh federation --add matrix.partner.ru"
                echo ""
                SERVERS=()
                while true; do
                    read -rp "$(echo -e "${BLUE}?${NC} Сервер (или Enter для завершения): ")" _SRV
                    [ -z "$_SRV" ] && break
                    fed_valid_domain "$_SRV" || { warn "Некорректный домен: ${_SRV}"; continue; }
                    SERVERS+=("$_SRV")
                    log "Добавлен: ${_SRV}"
                done
                if [ ${#SERVERS[@]} -eq 0 ]; then
                    warn "Список пустой — отменено"
                else
                    fed_write "${SERVERS[@]}"
                    log "Whitelist настроен (${#SERVERS[@]} серверов)"
                    fed_restart
                fi
                ;;
            2)
                fed_write
                log "Федерация закрыта — изолированный контур"
                fed_restart
                ;;
            3)
                fed_open
                log "Федерация открыта"
                fed_restart
                ;;
            *) warn "Отменено" ;;
        esac
        echo ""
        ;;

    verify-domain)
        [ -z "$TOKEN" ] && err "Укажите токен: ./manage.sh verify-domain --token <TOKEN>"
        DOMAIN=$(grep "^SYNAPSE_DOMAIN=" .env | cut -d= -f2)
        mkdir -p ./config/nginx/well-known
        printf '%s\n' "$TOKEN" > ./config/nginx/well-known/domain-verification
        docker compose exec -T nginx nginx -s reload >/dev/null 2>&1 || true
        log "Токен опубликован: https://${DOMAIN}/.well-known/domain-verification"
        _GOT=$(curl -sf --max-time 10 "https://${DOMAIN}/.well-known/domain-verification" 2>/dev/null | tr -d '\r\n' || true)
        if [ "$_GOT" = "$TOKEN" ]; then
            log "Проверка: токен читается снаружи"
        else
            warn "Снаружи токен пока не читается — подождите несколько секунд и проверьте: curl https://${DOMAIN}/.well-known/domain-verification"
        fi
        info "Второй способ подтверждения, если сервис его предлагает, — TXT-запись в DNS домена ${DOMAIN}"
        ;;

    backup-key)
        SERVER_NAME=$(grep "^SERVER_NAME=" .env | cut -d= -f2)
        KEY="./config/synapse/${SERVER_NAME}.signing.key"
        [ ! -f "$KEY" ] && err "Ключ не найден: ${KEY}"
        OUT="${OUT:-${HOME}/${SERVER_NAME}.signing.key}"
        mkdir -p "$(dirname "$OUT")"
        cp "$KEY" "$OUT" && chmod 600 "$OUT"
        log "Ключ подписи сохранён: ${OUT}"
        warn "Унесите файл с этого сервера (менеджер паролей, офлайн-носитель)."
        warn "Потеря ключа необратимо ломает федерацию — это единственный файл, который нельзя восстановить."
        ;;

    admin-token)
        DOMAIN=$(grep "^SYNAPSE_DOMAIN=" .env | cut -d= -f2)
        ADMIN_USER=$(grep "^INSTALL_ADMIN_USER=" .env | cut -d= -f2)
        if mas_enabled; then
            info "Выпускаем токен через MAS для ${ADMIN_USER}..."
            _TOK=$(mas_cli manage issue-compatibility-token --yes-i-want-to-grant-synapse-admin-privileges "${ADMIN_USER}" 2>&1) \
                || err "Не удалось выпустить токен: ${_TOK}"
            echo ""
            echo "$_TOK"
            echo ""
            info "Вставьте access token при входе в Synapse Admin UI"
        else
            read -rsp "$(echo -e "${BLUE}?${NC} Пароль ${ADMIN_USER}: ")" _PW; echo ""
            _TOK=$(curl -sf -X POST "https://${DOMAIN}/_matrix/client/v3/login" \
                -H "Content-Type: application/json" \
                -d "{\"type\":\"m.login.password\",\"user\":\"${ADMIN_USER}\",\"password\":\"${_PW}\"}" \
                2>/dev/null | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)
            [ -z "$_TOK" ] && err "Вход не удался"
            echo ""
            echo "$_TOK"
            echo ""
        fi
        ;;

    oidc)
        mas_enabled || err "Внешний вход требует MAS. Включите его: ./install.sh → режим «изменить настройки»"
        DOMAIN=$(grep "^SYNAPSE_DOMAIN=" .env | cut -d= -f2)
        SERVER_NAME=$(grep "^SERVER_NAME=" .env | cut -d= -f2)
        DB_PASS=$(grep "^POSTGRES_PASSWORD=" .env | cut -d= -f2)
        MAS_SECRET=$(grep "^MAS_SECRET=" .env | cut -d= -f2)
        _REG="false"; [ "$(hs_get enable_registration)" = "true" ] && _REG="true"

        if $OIDC_DISABLE; then
            OIDC_ISSUER=""; OIDC_CLIENT_ID=""; OIDC_NAME=""
        else
            [ -z "$OIDC_ISSUER" ] || [ -z "$OIDC_CLIENT_ID" ] && \
                err "Нужны оба параметра: ./manage.sh oidc --issuer https://... --client-id <ID> [--name Название]"
            [ -z "$OIDC_NAME" ] && OIDC_NAME=$(grep "^INSTALL_OIDC_NAME=" .env | cut -d= -f2)
        fi

        python3 lib/mas-config.py ./config/mas/config.yaml \
            --public-base "https://${DOMAIN}/" \
            --db-uri "postgresql://synapse:${DB_PASS}@postgres:5432/mas" \
            --server-name "${SERVER_NAME}" \
            --mas-secret "${MAS_SECRET}" \
            --password-registration "${_REG}" \
            --oidc-issuer "${OIDC_ISSUER}" \
            --oidc-client-id "${OIDC_CLIENT_ID}" \
            --oidc-name "${OIDC_NAME:-SSO}" || err "Не удалось обновить конфиг MAS"

        sed -i "s|^INSTALL_OIDC_ISSUER=.*|INSTALL_OIDC_ISSUER=${OIDC_ISSUER}|" .env
        sed -i "s|^INSTALL_OIDC_CLIENT_ID=.*|INSTALL_OIDC_CLIENT_ID=${OIDC_CLIENT_ID}|" .env
        sed -i "s|^INSTALL_OIDC_NAME=.*|INSTALL_OIDC_NAME=${OIDC_NAME}|" .env
        docker compose restart mas >/dev/null
        if $OIDC_DISABLE; then
            log "Внешний вход отключён"
        else
            log "Внешний вход включён: ${OIDC_ISSUER}"
            info "redirect_uri выше — его нужно зарегистрировать у провайдера"
        fi
        ;;

    mas)
        mas_enabled || err "MAS не включён"
        [ ${#MAS_ARGS[@]} -eq 0 ] && { mas_cli manage --help; exit 0; }
        mas_cli manage "${MAS_ARGS[@]}"
        ;;

    mas-migrate)
        mas_enabled || err "MAS не включён. Сначала включите его через install.sh, затем запустите перенос."
        echo ""
        info "syn2mas переносит аккаунты, пароли и устройства из Synapse в MAS."
        info "Проверка (check) безопасна. Перенос (--apply) требует остановленного Synapse."
        echo ""
        if $APPLY; then
            warn "Сделайте бэкап перед переносом: ./manage.sh backup"
            read -rp "$(echo -e "${YELLOW}?${NC} Остановить Synapse и выполнить перенос? [y/N]: ")" _C
            [[ "$_C" =~ ^[Yy]$ ]] || err "Отменено"
            docker compose stop synapse >/dev/null
            docker compose run --rm -v "$(pwd)/config/synapse:/synapse:ro" mas \
                syn2mas -c /config/config.yaml --synapse-config /synapse/homeserver.yaml migrate \
                && log "Перенос выполнен" || warn "Перенос завершился с ошибкой — смотрите вывод выше"
            docker compose start synapse >/dev/null
            log "Synapse запущен"
        else
            docker compose run --rm -v "$(pwd)/config/synapse:/synapse:ro" mas \
                syn2mas -c /config/config.yaml --synapse-config /synapse/homeserver.yaml check \
                && log "Проверка пройдена — можно запускать с --apply" \
                || warn "Проверка нашла проблемы — исправьте их до переноса"
        fi
        ;;

    password-reset)
        SERVER_NAME=$(grep "^SERVER_NAME=" .env | cut -d= -f2)
        ADMIN_USER=$(grep "^INSTALL_ADMIN_USER=" .env | cut -d= -f2)

        echo ""
        warn "Используйте эту команду только если вы не можете войти в Admin UI."
        warn "Для смены пароля обычного пользователя — зайдите в Admin UI → Users."
        echo ""
        info "Экстренный сброс пароля администратора через базу данных."
        echo ""
        read -rp "$(echo -e "${BLUE}?${NC} Логин пользователя [${ADMIN_USER}]: ")" _TARGET_USER
        _TARGET_USER="${_TARGET_USER:-$ADMIN_USER}"

        read -rsp "$(echo -e "${BLUE}?${NC} Новый пароль: ")" _NEW_PASS
        echo ""
        read -rsp "$(echo -e "${BLUE}?${NC} Повторите пароль: ")" _NEW_PASS2
        echo ""

        if [ "$_NEW_PASS" != "$_NEW_PASS2" ]; then
            err "Пароли не совпадают"
        fi
        if [ ${#_NEW_PASS} -lt 8 ]; then
            err "Пароль слишком короткий (минимум 8 символов)"
        fi

        if mas_enabled; then
            info "Меняем пароль через MAS..."
            mas_cli manage set-password --ignore-complexity "${_TARGET_USER}" "${_NEW_PASS}" >/dev/null && \
                log "Пароль @${_TARGET_USER}:${SERVER_NAME} изменён" || \
                err "MAS не принял пароль: ./manage.sh logs --service mas"
            echo ""
            exit 0
        fi

        info "Генерируем хэш пароля..."
        _HASH_OUTPUT=$(docker compose exec -T synapse hash_password -c /data/homeserver.yaml -p "$_NEW_PASS" 2>&1 | tr -d '\r\n')
        _HASH_CODE=$?
        if [ $_HASH_CODE -ne 0 ]; then
            err "Не удалось сгенерировать хэш: ${_HASH_OUTPUT}"
        fi
        if [ -n "$_HASH_OUTPUT" ] && echo "$_HASH_OUTPUT" | grep -q '^\$2'; then
            _HASH="$_HASH_OUTPUT"
        else
            err "Команда hash_password вернула неожиданный результат: ${_HASH_OUTPUT}"
        fi

        info "Обновляем пароль в базе данных..."
        docker compose exec -T postgres psql -U synapse -c \
            "UPDATE users SET password_hash='${_HASH}' WHERE name='@${_TARGET_USER}:${SERVER_NAME}';" \
            2>/dev/null && \
            log "Пароль @${_TARGET_USER}:${SERVER_NAME} успешно изменён" || \
            err "Не удалось обновить пароль. Проверьте что PostgreSQL запущен."
        echo ""
        ;;

    ssl-renew)
        DOMAIN=$(grep "^SYNAPSE_DOMAIN=" .env | cut -d= -f2)
        STACK=$(basename "$(pwd)")

        info "Принудительное обновление SSL-сертификата для ${DOMAIN}..."
        echo ""
        warn "nginx будет перезапущен после обновления сертификата."
        echo ""

        if docker run --rm \
            -v "${STACK}_certbot_certs:/etc/letsencrypt" \
            -v "${STACK}_certbot_www:/var/www/certbot" \
            certbot/certbot renew --webroot -w /var/www/certbot \
            --force-renewal --non-interactive \
            -d "${DOMAIN}"; then
            info "Перезапускаем nginx..."
            docker compose restart nginx
            log "Сертификат обновлён"
        else
            err "Не удалось обновить сертификат. Проверьте что порт 80 доступен и DNS настроен."
        fi

        # Показать срок действия нового сертификата
        CERT_EXPIRY=$(echo | openssl s_client -servername "$DOMAIN" -connect "${DOMAIN}:443" 2>/dev/null \
            | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
        [ -n "$CERT_EXPIRY" ] && log "Действителен до: ${CERT_EXPIRY}"
        echo ""
        ;;

    media-clean)
        STACK=$(basename "$(pwd)")

        echo ""
        info "Анализируем хранилище медиафайлов..."
        echo ""

        docker run --rm \
            -v "${STACK}_synapse_media:/media" \
            alpine sh -c '
                echo "  Размеры директорий:"
                printf "  %-20s %s\n" "local_content"  "$(du -sh /media/local_content  2>/dev/null | cut -f1 || echo "—")"
                printf "  %-20s %s\n" "remote_content" "$(du -sh /media/remote_content 2>/dev/null | cut -f1 || echo "—")"
                printf "  %-20s %s\n" "url_cache"      "$(du -sh /media/url_cache      2>/dev/null | cut -f1 || echo "—")"
                echo ""
                printf "  %-20s %s\n" "ИТОГО" "$(du -sh /media 2>/dev/null | cut -f1 || echo "—")"
            ' 2>/dev/null || warn "Не удалось получить размеры (проверьте что стек запущен)"

        echo ""
        echo "  Что можно очистить безопасно:"
        echo "  • url_cache      — кэш превью ссылок (восстанавливается автоматически)"
        echo "  • remote_content — файлы с других серверов (скачаются при следующем запросе)"
        echo ""
        echo "  НЕ трогаем:"
        echo "  • local_content  — файлы, загруженные вашими пользователями"
        echo ""
        read -rp "$(echo -e "${BLUE}?${NC} Очистить url_cache и remote_content? [y/N]: ")" _CLEAN_CONFIRM

        if [[ "$_CLEAN_CONFIRM" =~ ^[Yy]$ ]]; then
            read -rp "$(echo -e "${BLUE}?${NC} Хранить remote_content новее N дней (остальное удалить) [30]: ")" _DAYS
            _DAYS="${_DAYS:-30}"

            info "Очищаем url_cache..."
            docker run --rm \
                -v "${STACK}_synapse_media:/media" \
                alpine sh -c "rm -rf /media/url_cache/* 2>/dev/null; echo done" && \
                log "url_cache очищен"

            info "Очищаем remote_content старше ${_DAYS} дней..."
            docker run --rm \
                -v "${STACK}_synapse_media:/media" \
                alpine sh -c "find /media/remote_content -type f -mtime +${_DAYS} -delete 2>/dev/null; echo done" && \
                log "remote_content очищен"

            echo ""
            info "Размер после очистки:"
            docker run --rm \
                -v "${STACK}_synapse_media:/media" \
                alpine sh -c 'printf "  ИТОГО: %s\n" "$(du -sh /media 2>/dev/null | cut -f1)"' 2>/dev/null || true
            echo ""
        else
            warn "Отменено"
            echo ""
        fi
        ;;

    wipe)
        echo ""
        warn "Полная очистка удалит:"
        echo "  • контейнеры и docker volumes (БД, медиа, сертификаты)"
        echo "  • локальные файлы установки (.env, docker-compose.yml, backup.sh)"
        echo "  • сгенерированные конфиги Synapse/nginx и порт-лист"
        echo ""
        read -rp "$(echo -e "${RED}[!!]${NC} Для подтверждения введите WIPE: ")" _WIPE_CONFIRM
        if [ "$_WIPE_CONFIRM" != "WIPE" ]; then
            warn "Отменено"
            echo ""
            exit 0
        fi
        read -rp "$(echo -e "${RED}[!!]${NC} Точно выполнить полную очистку? [y/N]: ")" _WIPE_FINAL
        if [[ ! "$_WIPE_FINAL" =~ ^[Yy]$ ]]; then
            warn "Отменено"
            echo ""
            exit 0
        fi

        info "Останавливаем стек и удаляем контейнеры/тома..."
        docker compose down -v --remove-orphans 2>/dev/null || true

        info "Удаляем локальные файлы и сгенерированные конфиги..."
        rm -f ./.env ./docker-compose.yml ./backup.sh ./ports.txt
        rm -f ./config/nginx/matrix.conf ./config/nginx/matrix.conf.bak
        rm -f ./config/synapse/homeserver.yaml ./config/synapse/Dockerfile
        rm -f ./config/synapse/*.signing.key 2>/dev/null || true
        rm -rf ./config/element ./config/cinny ./config/coturn ./config/livekit
        rm -rf ./config/mas ./config/nginx/well-known

        # Крон бэкапов создаётся в /etc/cron.d/matrix-backup, удаляем при наличии прав.
        rm -f /etc/cron.d/matrix-backup 2>/dev/null || true

        log "Полная очистка завершена"
        info "Для новой установки выполните: ./install.sh"
        echo ""
        ;;

    *)
        err "Неизвестная команда: ${COMMAND}. Используйте --help"
        ;;

esac
