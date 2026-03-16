defmodule Chat.Crypto.MessageEncryptor do
  @moduledoc """
  Шифрование сообщений с использованием AES-256-GCM.

  Каждый сообщение шифруется уникальным IV (вектор инициализации),
  что гарантирует безопасность даже при одинаковом содержимом.
  """

  # 256 бит
  @aes_key_size 32
  # 96 бит для GCM
  @iv_size 12

  @doc """
  Шифрует сообщение.

  ## Возвращает
  %{ciphertext: binary, iv: binary, tag: binary}

  ## Примеры

      iex> %{ciphertext: ct, iv: iv, tag: tag} = encrypt("Hello")
      iex> is_binary(ct) and is_binary(iv) and is_binary(tag)
      true
  """
  def encrypt(plaintext) when is_binary(plaintext) do
    key = get_encryption_key()
    iv = :crypto.strong_rand_bytes(@iv_size)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        key,
        iv,
        plaintext,
        # AAD (additional authenticated data)
        "",
        # encrypt = true
        true
      )

    %{
      ciphertext: ciphertext,
      iv: iv,
      tag: tag
    }
  end

  @doc """
  Расшифровывает сообщение.

  ## Возвращает
  {:ok, plaintext} | {:error, :decryption_failed}

  ## Примеры

      iex> encrypted = encrypt("Hello")
      iex> decrypt(encrypted)
      {:ok, "Hello"}
  """

  def decrypt(%{ciphertext: ct, iv: iv, tag: tag}) do
    key = get_encryption_key()

    # 🔍 Отладка
    IO.inspect(
      %{
        key_size: byte_size(key),
        ciphertext_size: byte_size(ct),
        iv_size: byte_size(iv),
        tag_size: byte_size(tag)
      },
      label: "DECRYPT DEBUG"
    )

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ct, "", tag, false) do
      plaintext when is_binary(plaintext) ->
        {:ok, plaintext}

      error ->
        # 🔍 Логируем ошибку
        IO.inspect(error, label: "DECRYPT ERROR")
        {:error, :decryption_failed}
    end
  end

  def get_encryption_key do
    key =
      case Application.get_env(:chat, Chat.Crypto)[:encryption_key] do
        nil ->
          raise "Encryption key not configured!"

        key when byte_size(key) == @aes_key_size ->
          key

        key ->
          # 🔍 Логируем размер ключа
          IO.inspect(
            %{
              configured_size: byte_size(key),
              expected_size: @aes_key_size
            },
            label: "KEY SIZE MISMATCH"
          )

          raise "Invalid encryption key size (expected #{@aes_key_size} bytes, got #{byte_size(key)})"
      end

    key
  end

  @doc """
  Проверяет, что ключ настроен корректно.
  """
  def validate_key! do
    key = get_encryption_key()

    if byte_size(key) != @aes_key_size do
      raise "Encryption key must be #{@aes_key_size} bytes, got #{byte_size(key)}"
    end

    :ok
  end
end
