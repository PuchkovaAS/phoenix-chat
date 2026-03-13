# lib/chat/rooms.ex
defmodule Chat.Rooms do
  @moduledoc """
  Контекст для управления комнатами.
  """

  import Ecto.Query
  alias Chat.Repo
  alias Chat.Rooms.Room

  @doc """
  Создаёт новую комнату.
  """
  def create_room(attrs) do
    %Room{}
    |> Room.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Получает комнату по ID.
  """
  def get_room!(id), do: Repo.get!(Room, id)

  @doc """
  Получает комнату по имени (slug).
  """
  def get_room_by_name(name), do: Repo.get_by(Room, name: name)

  @doc """
  Список всех комнат.
  """
  def list_rooms do
    Room
    |> order_by(desc: :inserted_at)
    |> preload(:creator)
    |> Repo.all()
  end

  @doc """
  Обновляет комнату.
  """
  def update_room(%Room{} = room, attrs) do
    room
    |> Room.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Проверяет пароль комнаты.
  """
  def verify_password(%Room{password_hash: ""}, _password), do: true
  def verify_password(%Room{password_hash: ""}, nil), do: true

  def verify_password(%Room{password_hash: hash}, password) when is_binary(password) do
    Bcrypt.verify_pass(password, hash)
  end

  def verify_password(_, _), do: false

  @doc """
  Проверяет, может ли пользователь войти в комнату.
  """
  def can_access?(%Room{is_private: false}, _user), do: true
  def can_access?(%Room{creator_id: creator_id}, %{id: creator_id}), do: true
  def can_access?(%Room{}, %{id: _user_id}), do: true
  def can_access?(_, _), do: false
end
