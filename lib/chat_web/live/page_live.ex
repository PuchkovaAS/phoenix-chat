defmodule ChatWeb.PageLive do
  use ChatWeb, :live_view
  require Logger
  on_mount {ChatWeb.UserAuth, :require_authenticated}

  alias Chat.Rooms

  @impl true
  def mount(params, _session, socket) do
    rooms = Rooms.list_rooms()

    # ✅ Обработка return_url внутри одного mount
    return_url = Map.get(params, "return_url")

    # Если есть return_url — предзаполняем форму
    changeset =
      if return_url do
        room_id = return_url |> String.trim_leading("/") |> String.split("/") |> List.first()
        Rooms.Room.create_changeset(%Rooms.Room{}, %{name: room_id})
      else
        Rooms.Room.create_changeset(%Rooms.Room{}, %{})
      end

    {:ok,
     socket
     |> assign(:create_mode, false)
     |> assign(:rooms, rooms)
     |> assign(:room_changeset, changeset)
     |> assign(:return_url, return_url)}
  end

  # ✅ Переключение между входом и созданием
  @impl true
  def handle_event("toggle-create", _params, socket) do
    {:noreply, assign(socket, :create_mode, !socket.assigns.create_mode)}
  end

  # ✅ Заполнение формы из sidebar (для приватных комнат)
  @impl true
  def handle_event("fill-join-form", %{"room" => room_name}, socket) do
    changeset = Rooms.Room.create_changeset(%Rooms.Room{}, %{name: room_name})

    {:noreply,
     socket
     |> assign(:create_mode, false)
     |> assign(:room_changeset, changeset)}
  end

  # ✅ Создание случайной комнаты
  @impl true
  def handle_event("random-room", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    random_slug = MnemonicSlugs.generate_slug(4)

    case Rooms.create_room(%{
           name: random_slug,
           creator_id: user_id,
           is_private: false
         }) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: "/#{room.name}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create room")}
    end
  end

  # ✅ Вход в комнату (с проверкой пароля)
  @impl true
  def handle_event("join_room", %{"id" => room_id, "password" => password}, socket) do
    clean_id = room_id |> String.trim() |> String.trim_leading("#")

    case Rooms.get_room_by_name(clean_id) do
      nil ->
        user_id = socket.assigns.current_scope.user.id

        case Rooms.create_room(%{
               name: clean_id,
               password: password,
               creator_id: user_id,
               is_private: password != ""
             }) do
          {:ok, room} ->
            {:noreply, push_navigate(socket, to: "/#{room.name}")}

          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(:room_changeset, changeset)
             |> put_flash(:error, "Failed to create room")}
        end

      room ->
        if Rooms.verify_password(room, password) do
          # ✅ Просто редирект — защита в RoomLive через assigns
          {:noreply,
           socket
           |> put_flash(:info, "Welcome to #{room.name}!")
           |> push_navigate(to: "/#{clean_id}")}
        else
          changeset =
            Rooms.Room.create_changeset(%Rooms.Room{}, %{name: clean_id})
            |> Ecto.Changeset.add_error(:password, "Wrong password")

          {:noreply,
           socket
           |> assign(:room_changeset, changeset)
           |> put_flash(:error, "Wrong password")}
        end
    end
  end

  # ✅ Создание новой комнаты
  @impl true
  def handle_event("create_room", %{"room" => attrs}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Rooms.create_room(Map.put(attrs, "creator_id", user_id)) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: "/#{room.name}")}

      {:error, changeset} ->
        errors =
          changeset.errors |> Enum.map(fn {f, {m, _}} -> "#{f}: #{m}" end) |> Enum.join(", ")

        {:noreply,
         socket |> assign(:room_changeset, changeset) |> put_flash(:error, "Failed: #{errors}")}
    end
  end
end
