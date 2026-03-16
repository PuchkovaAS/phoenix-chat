#!/bin/sh
set -e

echo "Waiting for database to be ready..."

# Простая проверка доступности БД (парсинг URL)
# Извлекаем хост и порт из DATABASE_URL
DB_HOST=$(echo $DATABASE_URL | sed -n 's|.*@\([^:/]*\).*|\1|p')
DB_PORT=$(echo $DATABASE_URL | sed -n 's|.*:\([0-9]*\)/.*|\1|p')

# Если порт не указан в URL, по умолчанию 5432
if [ -z "$DB_PORT" ]; then
  DB_PORT=5432
fi

# Ждем подключения к порту БД
until nc -z "$DB_HOST" "$DB_PORT"; do
  echo "Database is unavailable - sleeping..."
  sleep 2
done

echo "Database is up! Running migrations..."

# Запуск миграций через команду eval релиза
/app/bin/chat eval "Chat.Release.migrate()"

echo "Migrations completed. Starting server..."

# Запуск самого сервера
exec /app/bin/chat start
