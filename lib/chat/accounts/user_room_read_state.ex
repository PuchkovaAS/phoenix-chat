defmodule Chat.Accounts.UserRoomReadState do
  @moduledoc """
  Отслеживает состояние прочтения сообщений.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "user_room_read_states" do
    belongs_to :user, Chat.Accounts.User
    field :room_id, :string
    # UUID из таблицы messages → используем type: :binary_id
    belongs_to :last_read_message, Chat.Messages.Message, type: :binary_id

    field :unread_count, :integer, default: 0
    field :last_seen_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(read_state, attrs) do
    read_state
    |> cast(attrs, [:user_id, :room_id, :last_read_message_id, :unread_count, :last_seen_at])
    |> validate_required([:user_id, :room_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:last_read_message_id)
    |> unique_constraint([:user_id, :room_id])
  end
end
