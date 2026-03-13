# priv/repo/migrations/*_create_messages.exs
defmodule Chat.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # ✅ ИСПРАВЛЕНО: room_id ссылается на rooms (uuid) с правильным типом
      add :room_id, references(:rooms, on_delete: :delete_all, type: :binary_id), null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :content_encrypted, :binary, null: false
      add :iv, :binary, null: false
      add :auth_tag, :binary, null: false
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
