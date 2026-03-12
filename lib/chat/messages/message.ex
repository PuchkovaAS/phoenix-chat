defmodule Chat.Messages.Message do
  @moduledoc """
  Схема сообщения с поддержкой шифрования.

  Сообщения хранятся в зашифрованном виде (AES-256-GCM) в базе данных.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Chat.Crypto.MessageEncryptor

  # ✅ ID сообщения — UUID
  @primary_key {:id, :binary_id, autogenerate: true}
  # ✅ Foreign key тип — :id (bigint) для совместимости с таблицей users
  @foreign_key_type :id

  schema "messages" do
    field :room_id, :string
    belongs_to :user, Chat.Accounts.User

    # Виртуальное поле для открытого текста (только для записи/чтения)
    field :content, :string, virtual: true

    # Зашифрованные поля в БД
    field :content_encrypted, :binary
    field :iv, :binary
    field :auth_tag, :binary

    # Метаданные
    field :metadata, :map, default: %{}
    field :edited_at, :utc_datetime
    field :deleted_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset для создания сообщения с шифрованием.

  ## Примеры

      iex> create_changeset(%Message{}, %{room_id: "room1", user_id: 1, content: "Hello"})
      %Ecto.Changeset{}
  """
  def create_changeset(message, attrs) do
    message
    |> cast(attrs, [:room_id, :content, :user_id, :metadata, :expires_at])
    |> validate_required([:room_id, :content, :user_id])
    |> validate_length(:content, min: 1, max: 10_000)
    |> validate_length(:room_id, min: 1, max: 255)
    |> foreign_key_constraint(:user_id)
    |> encrypt_content()
  end

  @doc """
  Changeset для обновления (например, пометка как удалённое или редактирование).
  """
  def update_changeset(message, attrs) do
    message
    |> cast(attrs, [
      :metadata,
      :edited_at,
      :deleted_at,
      :expires_at,
      :content_encrypted,
      :iv,
      :auth_tag
    ])
  end

  @doc """
  Расшифровывает сообщение и возвращает структуру с полем :content.

  ## Примеры

      iex> decrypt_content(message)
      %Message{content: "Расшифрованный текст"}
  """
  def decrypt_content(%__MODULE__{} = message) do
    case MessageEncryptor.decrypt(%{
           ciphertext: message.content_encrypted,
           iv: message.iv,
           tag: message.auth_tag
         }) do
      {:ok, plaintext} -> %{message | content: plaintext}
      {:error, _} -> %{message | content: "[Ошибка расшифровки]"}
    end
  end

  @doc """
  Шифрует контент сообщения перед сохранением.
  """
  defp encrypt_content(%Ecto.Changeset{valid?: true} = changeset) do
    case get_change(changeset, :content) do
      nil ->
        changeset

      plaintext ->
        %{ciphertext: ct, iv: iv, tag: tag} = MessageEncryptor.encrypt(plaintext)

        changeset
        |> put_change(:content_encrypted, ct)
        |> put_change(:iv, iv)
        |> put_change(:auth_tag, tag)
        # Удаляем открытый текст из changeset
        |> delete_change(:content)
    end
  end

  defp encrypt_content(changeset), do: changeset
end
