#!/bin/bash

set -euo pipefail

#-------------------------------------------------------------------------------
# КОНФИГУРАЦИЯ
#-------------------------------------------------------------------------------

# Цвета для вывода
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Параметры
TARGET_DIR="/opt/shvirtd-example-python"
REPO_URL="${1:-}"
BRANCH="${2:-main}"

#-------------------------------------------------------------------------------
# ФУНКЦИИ
#-------------------------------------------------------------------------------

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error()   { echo -e "${RED}[✗]${NC} $1" >&2; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Скрипт должен быть запущен от root (для работы с /opt)"
        log_info "Используйте: sudo ./deploy.sh <repo_url>"
        exit 1
    fi
}

check_deps() {
    log_info "Проверка зависимостей..."
    local deps=("git" "docker" "docker compose")
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            log_error "Зависимость не найдена: $dep"
            exit 127
        fi
    done
    log_success "Все зависимости установлены"
}

clone_repo() {
    local repo_url="$1"
    
    if [[ -z "$repo_url" ]]; then
        log_error "Не указан URL репозитория"
        log_info "Использование: $0 <repo_url> [branch]"
        exit 1
    fi
    
    log_info "Клонирование репозитория в ${TARGET_DIR}..."
    
    # Очистка, если директория уже существует
    if [[ -d "${TARGET_DIR}" ]]; then
        log_warn "Директория ${TARGET_DIR} уже существует, удаляю..."
        rm -rf "${TARGET_DIR}"
    fi
    
    # Клонирование
    git clone -b "${BRANCH}" --depth 1 "${repo_url}" "${TARGET_DIR}"
    
    if [[ $? -eq 0 ]]; then
        log_success "Репозиторий склонирован"
    else
        log_error "Ошибка при клонировании"
        exit 1
    fi
}

setup_env() {
    log_info "Настройка окружения..."
    
    cd "${TARGET_DIR}"
    
    # Создаём .env если не существует
    if [[ ! -f ".env" ]]; then
        log_info "Создание .env файла..."
        cat > .env << 'EOF'
# MySQL credentials
MYSQL_ROOT_PASSWORD=supersecretroot
MYSQL_DATABASE=virtd
MYSQL_USER=app_user
MYSQL_PASSWORD=supersecretpass
EOF
        log_success ".env создан"
    else
        log_warn ".env уже существует, пропускаем"
    fi
}

build_and_start() {
    log_info "Сборка и запуск проекта..."
    
    cd "${TARGET_DIR}"
    
    # Сборка и запуск через docker compose
    docker compose up -d --build
    
    if [[ $? -eq 0 ]]; then
        log_success "Проект запущен"
    else
        log_error "Ошибка при запуске проекта"
        exit 1
    fi
}

wait_and_test() {
    log_info "Ожидание инициализации сервисов (60 сек)..."
    sleep 60
    
    log_info "Проверка статуса сервисов..."
    docker compose ps
    
    # Проверка, что все сервисы healthy
    local unhealthy=$(docker compose ps --format json | jq -r '.[] | select(.Health != "healthy" and .Health != "") | .Name' 2>/dev/null || true)
    
    if [[ -n "$unhealthy" ]]; then
        log_warn "Сервисы не в статусе healthy: $unhealthy"
        log_info "Проверьте логи: docker compose logs <service>"
    else
        log_success "Все сервисы в статусе healthy"
    fi
    
    # Локальный тест
    log_info "Локальный тест приложения..."
    if curl -sf --max-time 10 http://127.0.0.1:8090 > /dev/null 2>&1; then
        log_success "Локальный тест пройден: http://127.0.0.1:8090"
    else
        log_warn "Локальный тест не пройден, проверьте логи"
        docker compose logs web --tail 20
    fi
}

show_info() {
    echo ""
    echo "════════════════════════════════════════"
    echo -e "${GREEN} Развёртывание завершено!${NC}"
    echo "════════════════════════════════════════"
    echo ""
    echo "Проект расположен: ${TARGET_DIR}"
    echo "Локальный доступ: http://127.0.0.1:8090"
    echo "Внешний доступ: http://<ВАШ_ВНЕШНИЙ_IP>:8090"
    echo ""
    echo "Полезные команды:"
    echo "  • Просмотр логов:     cd ${TARGET_DIR} && docker compose logs -f"
    echo "  • Остановка:          cd ${TARGET_DIR} && docker compose down"
    echo "  • Перезапуск:         cd ${TARGET_DIR} && docker compose restart"
    echo "  • Подключение к БД:   docker exec -ti mysql-db mysql -uroot -p"
    echo ""
    echo "Для внешнего тестирования:"
    echo "  1. Узнайте внешний IP: curl -s https://ifconfig.me"
    echo "  2. Протестируйте на:   https://check-host.net/check-http"
    echo "  3. URL для проверки:   http://<ВАШ_ВНЕШНИЙ_IP>:8090"
    echo ""
}

#-------------------------------------------------------------------------------
# ОСНОВНАЯ ЛОГИКА
#-------------------------------------------------------------------------------

main() {
    echo -e "${BLUE} Deploy Script for shvirtd-example-python${NC}"
    echo ""
    
    check_root
    check_deps
    clone_repo "${REPO_URL}"
    setup_env
    build_and_start
    wait_and_test
    show_info
}

# Запуск
main "$@"
