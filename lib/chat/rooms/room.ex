defmodule Chat.Rooms.Room do
  @moduledoc """
  Схема комнаты чата.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :id

  schema "rooms" do
    field :name, :string
    field :description, :string
    field :password_hash, :string, default: ""

    # ✅ Виртуальное поле для пароля из формы
    field :password, :string, virtual: true

    field :is_private, :boolean, default: false
    field :max_members, :integer, default: 100
    field :settings, :map, default: %{}

    belongs_to :creator, Chat.Accounts.User, type: :id
    has_many :messages, Chat.Messages.Message, foreign_key: :room_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset для создания комнаты.
  """
  def create_changeset(room, attrs) do
    room
    |> cast(attrs, [
      :name,
      :description,
      :password,
      :creator_id,
      :is_private,
      :max_members,
      :settings
    ])
    |> validate_required([:name, :creator_id])
    |> validate_length(:name, min: 3, max: 50)
    |> validate_length(:description, max: 500)
    |> validate_number(:max_members, greater_than: 0, less_than: 1000)
    |> unique_constraint(:name)
    |> foreign_key_constraint(:creator_id)
    |> put_password_hash()
  end

  @doc """
  Changeset для обновления комнаты.
  """
  def update_changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :description, :password, :is_private, :max_members, :settings])
    |> validate_length(:name, min: 3, max: 50)
    |> validate_length(:description, max: 500)
    |> validate_number(:max_members, greater_than: 0, less_than: 1000)
    |> unique_constraint(:name)
    |> put_password_hash()
  end

  # ✅ Исправленная функция хэширования
  defp put_password_hash(
         %Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset
       )
       when is_binary(password) and password != "" do
    put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
  end

  defp put_password_hash(changeset), do: changeset
end
