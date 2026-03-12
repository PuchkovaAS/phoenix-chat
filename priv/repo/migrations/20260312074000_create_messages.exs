defmodule Chat.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      # ID сообщения может быть UUID
      add :id, :binary_id, primary_key: true
      add :room_id, :string, null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Зашифрованные данные
      add :content_encrypted, :binary, null: false
      add :iv, :binary, null: false
      add :auth_tag, :binary, null: false

      # Метаданные
      add :metadata, :map, default: %{}
      add :edited_at, :utc_datetime
      add :deleted_at, :utc_datetime
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:room_id, :inserted_at])
    create index(:messages, [:user_id, :inserted_at])
    create index(:messages, [:deleted_at], where: "deleted_at IS NOT NULL")
    create index(:messages, [:expires_at], where: "expires_at IS NOT NULL")
  end
end
