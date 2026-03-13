# priv/repo/migrations/*_add_user_room_read_state.exs
defmodule Chat.Repo.Migrations.AddUserRoomReadState do
  use Ecto.Migration

  def change do
    create table(:user_room_read_states, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :room_id, :string, null: false

      add :last_read_message_id, references(:messages, on_delete: :nilify_all, type: :binary_id),
        null: true

      add :unread_count, :integer, default: 0, null: false
      add :last_seen_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_room_read_states, [:user_id, :room_id])
    create index(:user_room_read_states, [:room_id])
    create index(:user_room_read_states, [:last_read_message_id])
  end
end

