Шаг 0.1: Проверка системных требований
# Проверка версии операционной системы
cat /etc/os-release

# Проверка Docker
docker --version
# Ожидаемый результат: Docker version 20.10.x или выше

# Проверка Docker Compose
docker-compose --version
# Ожидаемый результат: docker-compose version 2.x.x

# Проверка Bash версии
bash --version
# Ожидаемый результат: GNU bash, version 4.0 или выше

# Проверка наличия cron
which cron || which crond
# Ожидаемый результат: /usr/sbin/cron или /usr/sbin/crond

# Проверка PostgreSQL клиента (если установлен)
psql --version
# Если не установлен - установим на следующем шаге

Шаг 0.2: Установка PostgreSQL клиентских инструментов
Что делаем: Устанавливаем утилиты psql, pg_dump, pg_basebackup на хостовую машину.

# Для Ubuntu/Debian:
sudo apt update
sudo apt install -y postgresql-client postgresql-client-common

# Для CentOS/RHEL:
sudo yum install -y postgresql

# Для Alpine Linux:
sudo apk add postgresql-client

# Проверка установки
psql --version
pg_dump --version
pg_basebackup --version

Шаг 0.3: Создание структуры директорий
Что делаем: Создаем организованную файловую структуру для всех файлов проекта.

# Создаем корневую директорию проекта
sudo mkdir -p /opt/pg-backup

# Переходим в неё
cd /opt/pg-backup

# Создаем поддиректории для скриптов
sudo mkdir -p scripts

# Создаем поддиректории для конфигураций
sudo mkdir -p config

# Создаем поддиректории для логов
sudo mkdir -p logs

# Создаем структуру для бэкапов
sudo mkdir -p /backup/dumps/full
sudo mkdir -p /backup/dumps/incremental
sudo mkdir -p /backup/basebackup
sudo mkdir -p /backup/wal_archives

# Устанавливаем владельца (замените $USER на вашего пользователя)
sudo chown -R $USER:$USER /opt/pg-backup
sudo chown -R $USER:$USER /backup

# Устанавливаем права доступа
sudo chmod -R 750 /opt/pg-backup
sudo chmod -R 750 /backup

# Проверяем структуру
tree /opt/pg-backup
# Если tree не установлен: find /opt/pg-backup -type d

Ожидаемая структура:
/opt/pg-backup/
├── config/
├── logs/
└── scripts/

/backup/
├── basebackup/
├── dumps/
│   ├── full/
│   └── incremental/
└── wal_archives/

Шаг 0.4: Настройка файла аутентификации .pgpass
Что делаем: Создаем файл для безопасного хранения паролей PostgreSQL.
# Переходим в директорию конфигураций
cd /opt/pg-backup/config

# Создаем файл .pgpass
nano .pgpass

# Вставляем содержимое (ЗАМЕНИТЕ на ваши реальные данные):
# Формат: hostname:port:database:username:password
localhost:5432:mydb:postgres:YourSecurePassword123
localhost:5432:*:postgres:YourSecurePassword123
127.0.0.1:5432:*:postgres:YourSecurePassword123

# Сохраняем файл: Ctrl+O, Enter, Ctrl+X

# Устанавливаем ПРАВИЛЬНЫЕ права (КРИТИЧНО ВАЖНО!)
chmod 600 /opt/pg-backup/config/.pgpass

# Проверяем права
ls -la /opt/pg-backup/config/.pgpass
# Ожидаемый результат: -rw------- (только владелец может читать)

# Устанавливаем переменную окружения
export PGPASSFILE=/opt/pg-backup/config/.pgpass

# Добавляем в ~/.bashrc для постоянства
echo 'export PGPASSFILE=/opt/pg-backup/config/.pgpass' >> ~/.bashrc
source ~/.bashrc

Шаг 0.5: Проверка подключения к PostgreSQL
Что делаем: Убеждаемся, что можем подключиться к базе данных.
# Находим имя контейнера PostgreSQL
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

# Запоминаем имя контейнера (например: postgresql)
CONTAINER_NAME="postgresql"

# Проверяем подключение из контейнера
docker exec -it $CONTAINER_NAME psql -U postgres -c "SELECT version();"

# Проверяем подключение с хоста (если порт 5432 открыт)
psql -h localhost -p 5432 -U postgres -d mydb -c "SELECT current_database();"

# Если подключение не работает, проверяем:
# 1. Запущен ли контейнер: docker ps
# 2. Открыт ли порт: docker port $CONTAINER_NAME
# 3. Правильный ли пароль в .pgpass
