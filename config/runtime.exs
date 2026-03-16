# config/runtime.exs
import Config

# ## Using releases
if System.get_env("PHX_SERVER") do
  config :chat, ChatWeb.Endpoint, server: true
end

# Порт для HTTP-сервера (читается из окружения)
config :chat, ChatWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT") || "4000")]

if config_env() == :prod do
  # --- База данных ---
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :chat, Chat.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # --- Секретный ключ ---
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # --- Хост и домены ---
  host = System.get_env("APP_HOST", "localhost")

  # Схема: https если за прокси, http если напрямую
  scheme = System.get_env("APP_SCHEME", "http")
  port = String.to_integer(System.get_env("APP_URL_PORT") || "443")

  # 🔥 Разрешённые источники для WebSocket (LiveView)
  allowed_origins =
    System.get_env("ALLOWED_ORIGINS", "#{scheme}://#{host}")
    |> String.split(",", trim: true)
    |> Enum.map(fn origin ->
      # Преобразуем "https://example.com" → "//example.com" для check_origin
      origin
      |> String.replace_prefix("http://", "//")
      |> String.replace_prefix("https://", "//")
    end)
    # Добавляем стандартные локальные адреса
    |> Enum.uniq()
    |> Kernel.++(["//localhost", "//127.0.0.1"])

  config :chat, ChatWeb.Endpoint,
    url: [host: host, port: port, scheme: scheme],
    http: [
      # Слушать все интерфейсы
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: secret_key_base,
    # 🔥 Ключевое исправление!
    check_origin: allowed_origins

  # force_ssl: [hsts: System.get_env("FORCE_SSL") in ~w(true 1)]

  # --- Ключ шифрования ---
  config :chat, Chat.Crypto,
    encryption_key:
      System.fetch_env!("CHAT_ENCRYPTION_KEY")
      |> Base.decode64!()

  # DNS cluster (опционально)
  config :chat, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
else
  # DEV/TEST окружение — более мягкие настройки
  config :chat, Chat.Crypto,
    encryption_key:
      System.get_env("CHAT_ENCRYPTION_KEY", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
      |> Base.decode64!()
end
