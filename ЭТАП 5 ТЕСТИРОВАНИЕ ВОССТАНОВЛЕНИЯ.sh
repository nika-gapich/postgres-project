Шаг 5.1: Создание скрипта проверки бэкапа
Что делаем: Создаем скрипт для проверки целостности бэкапов.
cd /opt/pg-backup/scripts
nano pg_verify_backup.sh

Вставляем код:
#!/bin/bash
################################################################################
# Скрипт проверки целостности backup
################################################################################

set -euo pipefail

BACKUP_DIR="/backup/dumps/full"
LOG_FILE="/opt/pg-backup/logs/pg_verify.log"
DATE_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo "[$DATE_HUMAN] $1" | tee -a "$LOG_FILE"
}

log "========== ПРОВЕРКА BACKUP =========="

# Поиск последнего бэкапа
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    log "ERROR: Backup файлы не найдены"
    exit 1
fi

log "Проверка файла: $LATEST_BACKUP"

# Проверка целостности gzip
log "Проверка целостности gzip..."
if gzip -t "$LATEST_BACKUP"; then
    log "✓ Gzip проверка: УСПЕШНО"
else
    log "✗ Gzip проверка: ПРОВАЛЕНА"
    exit 1
fi

# Проверка размера
FILE_SIZE=$(stat -c%s "$LATEST_BACKUP")
if [ "$FILE_SIZE" -gt 1000 ]; then
    log "✓ Размер файла: $(du -h "$LATEST_BACKUP" | cut -f1)"
else
    log "✗ Файл слишком маленький"
    exit 1
fi

log "========== ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ =========="
exit 0

chmod +x /opt/pg-backup/scripts/pg_verify_backup.sh
./pg_verify_backup.sh

Шаг 5.2: Создание скрипта тестового восстановления
Что делаем: Создаем скрипт для автоматического тестирования восстановления.
cd /opt/pg-backup/scripts
nano pg_restore_test.sh
Вставляем код:
#!/bin/bash
################################################################################
# Скрипт тестового восстановления из backup
################################################################################

set -euo pipefail

# ============================================
# КОНФИГУРАЦИЯ
# ============================================
BACKUP_DIR="/backup/dumps/full"
LOG_FILE="/opt/pg-backup/logs/pg_restore_test.log"
DATE_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

DB_HOST="localhost"
DB_PORT="5432"
DB_USER="postgres"
TEST_DB="test_restore_$(date +%Y%m%d_%H%M%S)"

# ============================================
# ФУНКЦИИ
# ============================================

log() {
    echo "[$DATE_HUMAN] $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "Очистка тестовой БД: $TEST_DB"
    dropdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" --if-exists "$TEST_DB" 2>/dev/null || true
}

# ============================================
# ОСНОВНАЯ ЧАСТЬ
# ============================================

log "========== НАЧАЛО ТЕСТА ВОССТАНОВЛЕНИЯ =========="

# Поиск последнего бэкапа
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    log "ERROR: Backup файлы не найдены"
    exit 1
fi

log "Используемый backup: $LATEST_BACKUP"
log "Тестовая БД: $TEST_DB"

# Экспортируем пароль
export PGPASSFILE="/opt/pg-backup/config/.pgpass"

# Создаем тестовую БД
log "Создание тестовой базы данных..."
createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$TEST_DB"

# Восстановление
log "Начало восстановления..."
START_TIME=$(date +%s)

if gunzip -c "$LATEST_BACKUP" | psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" >> "$LOG_FILE" 2>&1; then
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    log "✓ Восстановление завершено за ${DURATION} секунд"
    
    # Проверка количества таблиц
    TABLE_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" -t -c \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
    
    log "✓ Количество таблиц: $TABLE_COUNT"
    
    log "========== ТЕСТ ВОССТАНОВЛЕНИЯ УСПЕШЕН =========="
    log "Backup: $LATEST_BACKUP"
    log "Test DB: $TEST_DB"
    log "Tables: $TABLE_COUNT"
    log "Duration: ${DURATION}s"
    log "=================================================="
    
    # Очистка
    cleanup
    exit 0
else
    log "✗ ОШИБКА ВОССТАНОВЛЕНИЯ"
    cleanup
    exit 1
fi

chmod +x /opt/pg-backup/scripts/pg_restore_test.sh
bash -n /opt/pg-backup/scripts/pg_restore_test.sh

# Тестируем
./pg_restore_test.sh

# Смотрим логи
tail -50 /opt/pg-backup/logs/pg_restore_test.log
