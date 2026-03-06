defmodule ChatWeb.RoomLive do
  use ChatWeb, :live_view
  require Logger

  alias ChatWeb.Presence

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    topic = "room:" <> room_id
    username = MnemonicSlugs.generate_slug(2)

    if connected?(socket) do
      ChatWeb.Endpoint.subscribe(topic)
      Presence.track(self(), topic, username, %{username: username})
    end

    user_list = list_users(topic)
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(room_id: room_id, topic: topic, username: username)
      |> assign(:user_list, user_list)
      |> assign(:typing_users, [])
      |> assign(:last_message_user, nil)
      |> assign(:last_message_time, nil)
      |> stream(:messages, [
        %{
          id: UUID.uuid4(),
          message: "#{username} joined the chat",
          username: "system",
          timestamp: DateTime.to_iso8601(now),
          show_header: true
        }
      ])

    {:ok, socket}
  end

  @impl true
  def handle_event("submit_message", %{"message" => message}, socket) do
    now = DateTime.utc_now()
    show_header = should_show_header?(socket, socket.assigns.username, now)

    ChatWeb.Endpoint.broadcast(socket.assigns.topic, "new_message", %{
      id: UUID.uuid4(),
      message: message,
      username: socket.assigns.username,
      timestamp: DateTime.to_iso8601(now),
      show_header: show_header
    })

    ChatWeb.Endpoint.broadcast(socket.assigns.topic, "typing", %{
      username: socket.assigns.username,
      is_typing: false
    })

    {:noreply,
     socket
     |> push_event("clear_form", %{selector: "#chat-form"})
     |> assign(:last_message_user, socket.assigns.username)
     |> assign(:last_message_time, now)}
  end

  def handle_event("typing", %{"value" => value}, socket) do
    if String.trim(value) != "" do
      ChatWeb.Endpoint.broadcast(socket.assigns.topic, "typing", %{
        username: socket.assigns.username,
        is_typing: true
      })
    end

    {:noreply, socket}
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
    # ✅ Исправлено: используем from_iso8601 с pattern matching
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

  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "typing",
          payload: %{username: username, is_typing: is_typing}
        },
        socket
      ) do
    if username != socket.assigns.username do
      typing_users =
        if is_typing do
          Enum.uniq(socket.assigns.typing_users ++ [username])
        else
          List.delete(socket.assigns.typing_users, username)
        end

      {:noreply, assign(socket, :typing_users, typing_users)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: payload}, socket) do
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
        # Просто возвращаем время в формате ЧЧ:ММ
        Calendar.strftime(datetime, "%H:%M")

      {:error, _} ->
        ""
    end
  end
end
