defmodule ChatWeb.RoomLive do
  use ChatWeb, :live_view
  require Logger

  on_mount {ChatWeb.UserAuth, :require_authenticated}
  alias ChatWeb.Presence

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    topic = "room:" <> room_id

    username =
      case socket.assigns[:current_scope] do
        %{user: %{nickname: nickname}} when not is_nil(nickname) and nickname != "" ->
          Logger.info("Using nickname: #{nickname}")
          nickname

        %{user: %{email: email}} when not is_nil(email) ->
          Logger.info("Using email: #{email}")
          email

        _other ->
          Logger.warning("Fallback to anonymous")
          "anonymous"
      end

    if connected?(socket) do
      # Подписка на тему
      ChatWeb.Endpoint.subscribe(topic)
      # Track presence с key=username
      Presence.track(self(), topic, username, %{username: username})
    end

    user_list = list_users(topic)

    socket =
      socket
      |> assign(room_id: room_id, topic: topic, username: username)
      |> assign(:user_list, user_list)
      |> assign(:last_message_user, nil)
      |> assign(:last_message_time, nil)
      |> stream(:messages, [], reset: true)

    {:ok, socket}
  end

  # ✅ Критично: очистка Presence при уходе из LiveView
  @impl true
  def terminate(_reason, socket) do
    if connected?(socket) do
      Presence.untrack(socket.assigns.topic, socket.assigns.username)
    end

    :ok
  end

  @impl true
  def handle_event("submit_message", %{"message" => message}, socket) do
    # Пропускаем пустые сообщения
    if String.trim(message) == "" do
      {:noreply, socket}
    else
      now = DateTime.utc_now()
      show_header = should_show_header?(socket, socket.assigns.username, now)

      # ✅ Генерируем ID один раз
      message_id = UUID.uuid4()

      ChatWeb.Endpoint.broadcast(socket.assigns.topic, "new_message", %{
        id: message_id,
        message: message,
        username: socket.assigns.username,
        timestamp: DateTime.to_iso8601(now),
        show_header: show_header
      })

      {:noreply,
       socket
       # ✅ Очищаем форму через JS
       |> push_event("clear_form", %{selector: "#chat-form input"})
       |> assign(:last_message_user, socket.assigns.username)
       |> assign(:last_message_time, now)}
    end
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "new_message",
          payload: %{
            id: id,
            message: body,
            username: username,
            timestamp: timestamp,
            show_header: show_header
          }
        },
        socket
      ) do
    datetime =
      case DateTime.from_iso8601(timestamp) do
        {:ok, dt, _offset} -> dt
        {:error, _} -> DateTime.utc_now()
      end

    {:noreply,
     socket
     |> stream_insert(:messages, %{
       id: id,
       message: body,
       username: username,
       timestamp: timestamp,
       show_header: show_header
     })
     |> assign(:last_message_user, username)
     |> assign(:last_message_time, datetime)}
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: payload}, socket) do
    # ✅ Join: не показываем сообщение для себя
    payload.joins
    |> Map.keys()
    |> Enum.each(fn username ->
      if username != socket.assigns.username do
        now = DateTime.utc_now()
        show_header = should_show_header?(socket, "system", now)

        ChatWeb.Endpoint.broadcast(socket.assigns.topic, "new_message", %{
          id: UUID.uuid4(),
          message: "#{username} joined the chat",
          username: "system",
          timestamp: DateTime.to_iso8601(now),
          show_header: show_header
        })
      end
    end)

    # ✅ Leave: показываем для всех
    payload.leaves
    |> Map.keys()
    |> Enum.each(fn username ->
      now = DateTime.utc_now()
      show_header = should_show_header?(socket, "system", now)

      ChatWeb.Endpoint.broadcast(socket.assigns.topic, "new_message", %{
        id: UUID.uuid4(),
        message: "#{username} left the chat",
        username: "system",
        timestamp: DateTime.to_iso8601(now),
        show_header: show_header
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
      {:ok, datetime, _offset} ->
        Calendar.strftime(datetime, "%H:%M:%S")

      {:error, _} ->
        ""
    end
  end
end
