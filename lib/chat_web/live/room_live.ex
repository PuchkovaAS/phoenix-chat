defmodule ChatWeb.RoomLive do
  @moduledoc """
  LiveView для комнаты чата — без отслеживания прочитанных.
  """

  use ChatWeb, :live_view
  require Logger

  on_mount {ChatWeb.UserAuth, :require_authenticated}

  alias ChatWeb.Presence
  alias Chat.Messages
  alias Chat.Rooms

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    topic = "room:" <> room_id

    username =
      case socket.assigns[:current_scope] do
        %{user: %{nickname: nickname}} when not is_nil(nickname) and nickname != "" ->
          nickname

        _ ->
          "anonymous"
      end

    room = Rooms.get_room_by_name(room_id) || Rooms.get_room!(room_id)
    room_uuid = room.id

    # 🔐 Проверка доступа для приватных комнат
    if room.is_private && room.creator_id != socket.assigns.current_scope.user.id do
      {:ok,
       socket
       |> put_flash(:error, "This room is private. Please enter the password.")
       |> redirect(to: "/?return_url=/#{room_id}")}
    end

    if connected?(socket) do
      ChatWeb.Endpoint.subscribe(topic)
      Presence.track(self(), topic, username, %{username: username})
    end

    user_list = list_users(topic)
    messages = Messages.list_room_messages_simple(room_uuid, 50)

    socket =
      socket
      |> assign(room_id: room_id)
      |> assign(room_uuid: room_uuid)
      |> assign(topic: topic)
      |> assign(username: username)
      |> assign(:user_list, user_list)
      |> assign(:last_message_user, nil)
      |> assign(:last_message_time, nil)
      |> assign(:room, room)
      |> stream(:messages, messages, reset: true)

    {:ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if connected?(socket) do
      Presence.untrack(self(), socket.assigns.topic, socket.assigns.username)
    end

    :ok
  end

  @impl true
  def handle_event("submit_message", %{"message" => content}, socket) do
    if String.trim(content) == "" do
      {:noreply, socket}
    else
      now = DateTime.truncate(DateTime.utc_now(), :second)
      show_header = should_show_header?(socket, socket.assigns.username, now)
      user = socket.assigns.current_scope.user

      case Messages.create_message(user, %{
             room_id: socket.assigns.room_uuid,
             content: content
           }) do
        {:ok, _message} ->
          ChatWeb.Endpoint.broadcast(socket.assigns.topic, "new_message", %{
            id: UUID.uuid4(),
            message: content,
            username: socket.assigns.username,
            timestamp: DateTime.to_iso8601(now),
            show_header: show_header
          })

          {:noreply,
           socket
           |> push_event("clear_form", %{selector: "#chat-form input"})
           |> assign(:last_message_user, socket.assigns.username)
           |> assign(:last_message_time, now)}

        {:error, changeset} ->
          Logger.error("Failed to create message: #{inspect(changeset.errors)}")
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
    end
  end

  @impl true
  def handle_event("scroll_to_bottom", _params, socket) do
    {:noreply, push_patch(socket, to: socket.assigns.live_action)}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "new_message"} = broadcast, socket) do
    {:noreply, socket |> stream_insert(:messages, broadcast.payload)}
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: payload}, socket) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    payload.joins
    |> Map.keys()
    |> Enum.each(fn username ->
      if username != socket.assigns.username do
        ChatWeb.Endpoint.broadcast(socket.assigns.topic, "new_message", %{
          id: UUID.uuid4(),
          message: "#{username} joined the chat",
          username: "system",
          timestamp: DateTime.to_iso8601(now),
          show_header: true
        })
      end
    end)

    payload.leaves
    |> Map.keys()
    |> Enum.each(fn username ->
      ChatWeb.Endpoint.broadcast(socket.assigns.topic, "new_message", %{
        id: UUID.uuid4(),
        message: "#{username} left the chat",
        username: "system",
        timestamp: DateTime.to_iso8601(now),
        show_header: true
      })
    end)

    user_list = list_users(socket.assigns.topic)
    {:noreply, assign(socket, :user_list, user_list)}
  end

  defp should_show_header?(socket, current_user, current_time) do
    last_user = socket.assigns[:last_message_user]
    last_time = socket.assigns[:last_message_time]

    cond do
      is_nil(last_user) -> true
      last_user != current_user -> true
      !is_nil(last_time) && DateTime.diff(current_time, last_time, :second) > 300 -> true
      true -> false
    end
  end

  defp list_users(topic) do
    topic
    |> Presence.list()
    |> Map.keys()
    |> Enum.map(fn username -> %{username: username} end)
  end

  defp format_time(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, utc_datetime, _offset} ->
        local = DateTime.add(utc_datetime, 3 * 3600, :second)
        Calendar.strftime(local, "%H:%M:%S")

      {:error, _} ->
        ""
    end
  end
end
