# priv/repo/migrations/*_create_rooms.exs
defmodule Chat.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      # ✅ UUID для самой комнаты
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :password_hash, :string, default: ""

      # ✅ ИСПРАВЛЕНО: users.id — это :id (bigint), поэтому type: :binary_id НЕ нужен
      add :creator_id, references(:users, on_delete: :nilify_all), null: true

      add :is_private, :boolean, default: false
      add :max_members, :integer, default: 100
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:rooms, [:creator_id])
    create unique_index(:rooms, [:name])
  end
end
