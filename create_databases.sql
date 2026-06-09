
1. Общая архитектура взаимодействия
text
docker-compose.yml
  └── service: postgres:16-alpine
      ├── volumes:
      │    ├── ./init-scripts:/docker-entrypoint-initdb.d
      │    └── postgres_data:/var/lib/postgresql/data
      ├── environment:
      │    POSTGRES_USER: super_admin   (только для инициализации)
      │    POSTGRES_PASSWORD: (сильный пароль)
      │    POSTGRES_DB: template_main
Принцип:

POSTGRES_USER — это одноразовый суперпользователь, который создаёт структуру и обычных пользователей.

После инициализации приложение использует ограниченных пользователей с минимальными привилегиями.

2. Скрипты инициализации (в правильном порядке)
Все скрипты кладутся в папку ./init-scripts/.
PostgreSQL выполняет их в алфавитном порядке.

2.1 01_create_app_users.sql
Создаём роли с разными уровнями доступа.

sql
-- 01_create_app_users.sql
-- Запускается от суперпользователя (POSTGRES_USER)

-- 1. Роль для чтения данных (SELECT ONLY)
CREATE ROLE app_readonly WITH LOGIN PASSWORD 'strong_pwd_readonly';
GRANT CONNECT ON DATABASE app_db TO app_readonly;

-- 2. Роль для чтения и записи (CRUD)
CREATE ROLE app_readwrite WITH LOGIN PASSWORD 'strong_pwd_rw';
GRANT CONNECT ON DATABASE app_db TO app_readwrite;

-- 3. Роль для миграций / DDL (создание/изменение таблиц)
CREATE ROLE app_migration WITH LOGIN PASSWORD 'strong_pwd_migrate';
GRANT CONNECT ON DATABASE app_db TO app_migration;

-- 4. Роль для резервного копирования (pg_dump)
CREATE ROLE app_backup WITH LOGIN PASSWORD 'strong_pwd_backup';
GRANT CONNECT ON DATABASE app_db TO app_backup;

-- Отзываем права на создание объектов в public schema у всех, кроме app_migration
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
2.2 02_create_custom_database.sql
Создаём базу для основного сервиса.

sql
-- 02_create_custom_database.sql
CREATE DATABASE app_db
    WITH 
    OWNER = app_migration
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0
    CONNECTION LIMIT = 100;
2.3 03_assign_schema_privileges.sql
Настраиваем права по принципу наименьших привилегий.

sql
-- 03_assign_schema_privileges.sql
\c app_db

-- Отключаем наследование прав от public
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO app_readonly, app_readwrite, app_migration;

-- Для читающей роли: только SELECT на существующие и будущие таблицы
ALTER DEFAULT PRIVILEGES FOR ROLE app_migration IN SCHEMA public 
    GRANT SELECT ON TABLES TO app_readonly;

-- Для读写 роли: SELECT, INSERT, UPDATE, DELETE
ALTER DEFAULT PRIVILEGES FOR ROLE app_migration IN SCHEMA public 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_readwrite;

-- Для миграционной роли: все права (включая DDL)
GRANT ALL PRIVILEGES ON SCHEMA public TO app_migration;
ALTER DEFAULT PRIVILEGES FOR ROLE app_migration IN SCHEMA public 
    GRANT ALL ON TABLES TO app_migration;

-- Для роли бэкапа: разрешаем только чтение и vacuum
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_backup;
GRANT USAGE ON SCHEMA public TO app_backup;
2.4 04_create_audit_and_logging.sql
Опционально: таблицы аудита с отдельными правами.

sql
-- 04_create_audit_and_logging.sql
\c app_db

CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    action TEXT NOT NULL,
    table_name TEXT,
    old_data JSONB,
    new_data JSONB,
    changed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Даже readwrite не может менять audit_log
GRANT INSERT, SELECT ON audit_log TO app_readwrite;
REVOKE DELETE, UPDATE ON audit_log FROM app_readwrite;

-- Только migration может менять структуру audit_log
GRANT ALL ON audit_log TO app_migration;
3. Dockerfile для расширенного контроля (если нужны дополнительные оптимизации)
Если стандартного образа недостаточно:

dockerfile
FROM postgres:16-alpine

# Копируем пользовательский конфиг для оптимизации
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY init-scripts/ /docker-entrypoint-initdb.d/

# Настройка прав на скрипты (чтобы они были исполняемыми)
RUN chmod -R 755 /docker-entrypoint-initdb.d/

CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
Пример postgresql.conf (оптимизация для контейнера):

text
shared_buffers = 256MB
effective_cache_size = 768MB
work_mem = 8MB
maintenance_work_mem = 64MB
max_connections = 50
log_statement = 'ddl'   # логировать только изменения схемы
log_connections = on
log_disconnections = on
4. Проверка принципа наименьших прав
После запуска контейнера проверяем:

bash
# Подключаемся от app_readonly
docker exec -it postgres_container psql -U app_readonly -d app_db

app_db=> SELECT * FROM users;   -- OK
app_db=> INSERT INTO users VALUES (...);  -- ERROR: permission denied
app_db=> CREATE TABLE test();   -- ERROR

# Подключаемся от app_readwrite
docker exec -it postgres_container psql -U app_readwrite -d app_db

app_db=> INSERT INTO users VALUES (...);  -- OK
app_db=> DELETE FROM audit_log;  -- ERROR
5. Расширенная оптимизация для production
5.1 Ресурсы в docker-compose
yaml
services:
  postgres:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          memory: 512M
5.2 Автоматический vacuum и анализ
Создаём 05_auto_vacuum_tune.sql:

sql
-- Устанавливаем пороги для часто обновляемых таблиц
ALTER TABLE app_db.public.orders SET (
    autovacuum_vacuum_scale_factor = 0.05,
    autovacuum_vacuum_threshold = 1000,
    autovacuum_analyze_scale_factor = 0.02
);
5.3 Мониторинг прав
Периодический скрипт для проверки:

sql
-- 06_audit_permissions.sql
SELECT grantee, privilege_type 
FROM information_schema.role_table_grants 
WHERE table_name = 'users'
ORDER BY grantee;
6. Документация для команды
Роль	Пароль (пример)	Доступ	Используется для
app_readonly	ro_7xK#mP2	Только SELECT	Отчёты, аналитика, UI чтение
app_readwrite	rw_9L#sD1	INSERT, UPDATE, DELETE, SELECT	API приложения
app_migration	mig_3Rt#zA9	CREATE, ALTER, DROP + все права	Миграции схемы (Liquibase)
app_backup	bkp_6Wq#eF4	SELECT, pg_dump, vacuum	Резервное копирование
7. Итоговая структура проекта
text
project/
├── docker-compose.yml
├── postgres/
│   ├── Dockerfile
│   ├── postgresql.conf
│   └── init-scripts/
│       ├── 01_create_app_users.sql
│       ├── 02_create_custom_database.sql
│       ├── 03_assign_schema_privileges.sql
│       ├── 04_create_audit_and_logging.sql
│       ├── 05_auto_vacuum_tune.sql
│       └── 06_audit_permissions.sql
└── .env (хранит пароли, не в git)
