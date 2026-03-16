
#!/bin/bash

echo "🛑 Останавливаем все контейнеры..."
docker stop $(docker ps -aq) 2>/dev/null

echo "🗑️ Удаляем все контейнеры..."
docker rm $(docker ps -aq) 2>/dev/null

echo "🖼️ Удаляем все образы..."
docker rmi $(docker images -q) 2>/dev/null

echo "📦 Удаляем все volumes..."
docker volume rm $(docker volume ls -q) 2>/dev/null

echo "🕸️ Удаляем пользовательские сети..."
docker network rm $(docker network ls -q --filter "type=custom") 2>/dev/null

echo "🧹 Чистим build-кэш..."
docker builder prune -a -f

echo "✅ Docker полностью очищен!"
