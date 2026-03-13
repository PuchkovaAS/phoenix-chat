defmodule Chat.Messages.Message do
  @moduledoc """
  Схема сообщения с поддержкой шифрования.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Chat.Crypto.MessageEncryptor

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :id

  schema "messages" do
    # ✅ belongs_to автоматически создаёт поле room_id
    belongs_to :room, Chat.Rooms.Room, type: :binary_id
    belongs_to :user, Chat.Accounts.User, type: :id

    field :content, :string, virtual: true
    field :content_encrypted, :binary
    field :iv, :binary
    field :auth_tag, :binary
    field :metadata, :map, default: %{}
    field :edited_at, :utc_datetime
    field :deleted_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def create_changeset(message, attrs) do
    message
    |> cast(attrs, [:room_id, :content, :user_id, :metadata, :expires_at])
    |> validate_required([:room_id, :content, :user_id])
    |> validate_length(:content, min: 1, max: 10_000)
    |> validate_length(:room_id, min: 1, max: 255)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:room_id)
    |> encrypt_content()
  end

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
        |> delete_change(:content)
    end
  end

  defp encrypt_content(changeset), do: changeset
end
