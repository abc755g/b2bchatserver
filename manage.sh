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
    echo "  federation         Управление федерацией"
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
shift || true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --service) SERVICE="$2"; shift 2 ;;
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
        docker compose pull
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

        case "$_REG_CHOICE" in
            1)
                hs_set "enable_registration" "false"
                info "Перезапускаем Synapse..."
                docker compose restart synapse
                log "Регистрация закрыта"
                ;;
            2)
                warn "Любой сможет создать аккаунт на вашем сервере!"
                read -rp "$(echo -e "${YELLOW}?${NC} Подтвердить? [y/N]: ")" _CONFIRM
                if [[ "$_CONFIRM" =~ ^[Yy]$ ]]; then
                    hs_set "enable_registration" "true"
                    info "Перезапускаем Synapse..."
                    docker compose restart synapse
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

        # Определяем текущий режим
        CURRENT_MODE="open"
        if grep -q "^federation_domain_whitelist:" "$HOMESERVER_YAML" 2>/dev/null; then
            WHITELIST=$(grep -A 20 "^federation_domain_whitelist:" "$HOMESERVER_YAML" | grep "^  - " | awk '{print $2}')
            if [ -z "$WHITELIST" ]; then
                CURRENT_MODE="closed"
            else
                CURRENT_MODE="whitelist"
            fi
        fi

        echo ""
        case "$CURRENT_MODE" in
            open)      log  "Федерация сейчас: ОТКРЫТАЯ — общение со всем Matrix-миром" ;;
            closed)    warn "Федерация сейчас: ЗАКРЫТАЯ — изолированный контур" ;;
            whitelist) log  "Федерация сейчас: WHITELIST — только разрешённые серверы:"
                       grep -A 20 "^federation_domain_whitelist:" "$HOMESERVER_YAML" | \
                           grep "^  - " | awk '{print "    " $2}' ;;
        esac

        echo ""
        echo "  [1] Открытая    — общение со всем Matrix-миром"
        echo "  [2] Закрытая    — изолированный контур, нет общения с внешними серверами"
        echo "  [3] Whitelist   — только указанные серверы"
        echo "  [4] Отмена"
        echo ""
        read -rp "$(echo -e "${BLUE}>>${NC} Выбор: ")" _FED_CHOICE

        case "$_FED_CHOICE" in
            1)
                hs_remove_block "federation_domain_whitelist"
                hs_set "block_non_local_invites" "false"
                hs_set "allow_public_rooms_over_federation" "true"
                info "Перезапускаем Synapse..."
                docker compose restart synapse
                log "Федерация открыта"
                ;;
            2)
                hs_remove_block "federation_domain_whitelist"
                # Пустой whitelist = блокировать всех
                printf "\nfederation_domain_whitelist: []\n" >> "$HOMESERVER_YAML"
                hs_set "block_non_local_invites" "true"
                hs_set "allow_public_rooms_over_federation" "false"
                info "Перезапускаем Synapse..."
                docker compose restart synapse
                log "Федерация закрыта — изолированный контур"
                ;;
            3)
                echo ""
                echo "  Введите домены серверов через Enter. Пустая строка — завершить."
                echo "  Пример: matrix.partner.ru"
                echo ""
                SERVERS=()
                while true; do
                    read -rp "$(echo -e "${BLUE}?${NC} Сервер (или Enter для завершения): ")" _SRV
                    [ -z "$_SRV" ] && break
                    SERVERS+=("$_SRV")
                    log "Добавлен: ${_SRV}"
                done

                if [ ${#SERVERS[@]} -eq 0 ]; then
                    warn "Список пустой — отменено"
                else
                    hs_remove_block "federation_domain_whitelist"
                    printf "\nfederation_domain_whitelist:\n" >> "$HOMESERVER_YAML"
                    for srv in "${SERVERS[@]}"; do
                        printf "  - %s\n" "$srv" >> "$HOMESERVER_YAML"
                    done
                    hs_set "block_non_local_invites" "true"
                    hs_set "allow_public_rooms_over_federation" "false"
                    info "Перезапускаем Synapse..."
                    docker compose restart synapse
                    log "Whitelist настроен (${#SERVERS[@]} серверов)"
                fi
                ;;
            *) warn "Отменено" ;;
        esac
        echo ""
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
