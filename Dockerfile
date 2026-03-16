# Этап 1: Сборка
FROM hexpm/elixir:1.19.3-erlang-28.0-debian-bullseye-20251117 AS build

# 🔥 ВАЖНО: Устанавливаем prod окружение СРАЗУ после FROM
ENV MIX_ENV=prod

# Установка зависимостей для сборки
RUN apt-get update && apt-get install -y build-essential git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Копируем файлы зависимостей
COPY mix.exs mix.lock ./
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod

# Копируем исходный код
COPY config config
COPY lib lib
COPY priv priv

# 🔥 Компиляция с правильным синтаксисом (+ вместо запятой)
RUN mix deps.compile && mix release

# Этап 2: Рантайм (ОБЯЗАТЕЛЬНО тот же базовый образ!)
FROM hexpm/elixir:1.19.3-erlang-28.0-debian-bullseye-20251117 AS app

# 🔥 Тоже устанавливаем prod
ENV MIX_ENV=prod

# Установка зависимостей для запуска
RUN apt-get update && \
    apt-get install -y openssl ca-certificates netcat-openbsd && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Копируем релиз из этапа сборки
# ЗАМЕНИТЕ 'chat' на имя вашего приложения из mix.exs
COPY --from=build /app/_build/prod/rel/chat ./

# Копируем скрипт запуска
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]
