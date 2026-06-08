Шаг 1.1: Создание скрипта архивации WAL
Что делаем: Создаем bash-скрипт, который будет копировать WAL-файлы в архивную директорию.
# Переходим в директорию скриптов
cd /opt/pg-backup/scripts

# Создаем файл скрипта
nano wal_archive.sh

Вставляем следующий код:
#!/bin/bash
################################################################################
# Скрипт архивации WAL-файлов PostgreSQL
# Вызывается PostgreSQL через archive_command
# Параметры: %p (путь к файлу) %f (имя файла)
################################################################################

set -euo pipefail

# Получаем параметры от PostgreSQL
WAL_SOURCE="$1"
WAL_FILENAME="$2"

# Конфигурация
ARCHIVE_BASE_DIR="/backup/wal_archives"
ARCHIVE_DIR="$ARCHIVE_BASE_DIR/$(date +%Y/%m/%d)"
LOG_FILE="/opt/pg-backup/logs/wal_archive.log"

# Функция логирования
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Создаем директорию архива если её нет
if [ ! -d "$ARCHIVE_DIR" ]; then
    mkdir -p "$ARCHIVE_DIR"
    log_message "INFO" "Создана директория: $ARCHIVE_DIR"
fi

# Проверяем существование исходного файла
if [ ! -f "$WAL_SOURCE" ]; then
    log_message "ERROR" "Файл не найден: $WAL_SOURCE"
    exit 1
fi

# Проверяем, не архивирован ли файл уже
if [ -f "$ARCHIVE_DIR/$WAL_FILENAME" ]; then
    log_message "WARN" "Файл уже существует: $WAL_FILENAME"
    exit 0
fi

# Копируем файл
if cp "$WAL_SOURCE" "$ARCHIVE_DIR/$WAL_FILENAME"; then
    log_message "INFO" "Успешно архивирован: $WAL_FILENAME"
    exit 0
else
    log_message "ERROR" "Ошибка архивации: $WAL_FILENAME"
    exit 1
fi

# Сохраняем файл: Ctrl+O, Enter, Ctrl
