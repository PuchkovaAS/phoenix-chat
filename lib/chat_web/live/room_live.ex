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
    messages = Messages.list_room_messages(room_id, 50)

    # ✅ ВАЖНО: Сохраняем количество сообщений в assigns
    socket =
      socket
      |> assign(room_id: room_id, topic: topic, username: username)
      |> assign(:user_list, user_list)
      |> assign(:last_message_user, nil)
      |> assign(:last_message_time, nil)
      # ← Новый аргумент
      |> assign(:messages_count, length(messages))
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
      now = DateTime.utc_now()
      show_header = should_show_header?(socket, socket.assigns.username, now)

      user_id = socket.assigns.current_scope.user.id

      case Messages.create_message(%{
             room_id: socket.assigns.room_id,
             user_id: user_id,
             content: content
           }) do
        # ← message не нужен
        {:ok, _message} ->
          ChatWeb.Endpoint.broadcast(socket.assigns.topic, "new_message", %{
            # ← Или используйте message.id если нужно
            id: UUID.uuid4(),
            # ← ИСПРАВЛЕНО: используем content
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
    payload.joins
    |> Map.keys()
    |> Enum.each(fn username ->
      if username != socket.assigns.username do
        now = DateTime.utc_now()

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
      now = DateTime.utc_now()

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

  # ✅ ВОЗВРАЩАЕМ ФУНКЦИЮ format_time/1 для шаблона
  defp format_time(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, utc_datetime, _offset} ->
        # Конвертация в нужный часовой пояс
        # Вариант А: по имени (требуется Timex)
        # {:ok, local} = Timex.Timezone.convert(utc_datetime, "Europe/Moscow")

        # Вариант Б: по смещению (без зависимостей)
        # Например, +3 часа для Москвы
        local = DateTime.add(utc_datetime, 3 * 3600, :second)

        Calendar.strftime(local, "%H:%M:%S")

      {:error, _} ->
        ""
    end
  end
end
