defmodule ChatWeb.RoomLive do
  @moduledoc """
  LiveView для комнаты чата с поддержкой зашифрованных сообщений.
  """

  use ChatWeb, :live_view
  require Logger

  on_mount {ChatWeb.UserAuth, :require_authenticated}

  alias ChatWeb.Presence
  alias Chat.Messages

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    topic = "room:" <> room_id

    username =
      case socket.assigns[:current_scope] do
        %{user: %{nickname: nickname}} when not is_nil(nickname) and nickname != "" ->
          Logger.info("Using nickname: #{nickname}")
          nickname

        _other ->
          Logger.warning("Fallback to anonymous (no nickname)")
          "anonymous"
      end

    if connected?(socket) do
      ChatWeb.Endpoint.subscribe(topic)
      Presence.track(self(), topic, username, %{username: username})
    end

    user_list = list_users(topic)
    user_id = socket.assigns.current_scope.user.id
    read_state = Messages.get_read_state(user_id, room_id)

    messages = Messages.list_room_messages(room_id, 50, nil, user_id)
    unread_count = Messages.count_unread_messages(user_id, room_id)

    # 🔍 Отладка
    IO.inspect("=== MOUNT DEBUG ===", label: "ROOM")
    IO.inspect(unread_count, label: "unread_count")
    IO.inspect(length(messages), label: "messages count")

    socket =
      socket
      |> assign(room_id: room_id || "")
      |> assign(topic: topic)
      |> assign(username: username || "anonymous")
      |> assign(:user_list, user_list || [])
      |> assign(user_id: user_id)
      |> assign(read_state: read_state)
      |> assign(unread_count: unread_count || 0)
      |> assign(:last_message_user, nil)
      |> assign(:last_message_time, nil)
      |> assign(:messages_count, length(messages) || 0)
      |> stream(:messages, messages || [], reset: true)

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
    if String.trim(content || "") == "" do
      {:noreply, socket}
    else
      now = DateTime.truncate(DateTime.utc_now(), :second)
      show_header = should_show_header?(socket, socket.assigns.username, now)
      user = socket.assigns.current_scope.user

      case Messages.create_message(user, %{
             room_id: socket.assigns.room_id,
             content: content
           }) do
        {:ok, _message} ->
          ChatWeb.Endpoint.broadcast(socket.assigns.topic, "new_message", %{
            id: UUID.uuid4(),
            message: content || "",
            username: socket.assigns.username || "anonymous",
            timestamp: DateTime.to_iso8601(now),
            show_header: show_header,
            is_read: true
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
  def handle_event(
        "mark_as_read",
        %{"message_id" => message_id, "timestamp" => _timestamp},
        socket
      ) do
    if socket.assigns[:user_id] do
      Task.start(fn ->
        Process.sleep(500)
        Messages.update_read_state(socket.assigns.user_id, socket.assigns.room_id, message_id)
      end)
    end

    {:noreply, assign(socket, :unread_count, 0)}
  end

  @impl true
  def handle_event("scroll_to_bottom", _params, socket) do
    {:noreply, push_patch(socket, to: socket.assigns.live_action)}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "new_message", payload: %{username: username}} =
          broadcast,
        socket
      )
      when username != socket.assigns.username do
    new_count = (socket.assigns.unread_count || 0) + 1

    {:noreply,
     socket |> assign(:unread_count, new_count) |> stream_insert(:messages, broadcast.payload)}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "new_message"} = broadcast, socket) do
    {:noreply, socket |> assign(:unread_count, 0) |> stream_insert(:messages, broadcast.payload)}
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
          show_header: true,
          is_read: true
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
        show_header: true,
        is_read: true
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
    case DateTime.from_iso8601(timestamp || "") do
      {:ok, utc_datetime, _offset} ->
        local = DateTime.add(utc_datetime, 3 * 3600, :second)
        Calendar.strftime(local, "%H:%M:%S")

      {:error, _} ->
        ""
    end
  end
end
