defmodule ChatWeb.RoomLive do
  use ChatWeb, :live_view
  require Logger

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    topic = "room:" <> room_id
    username = MnemonicSlugs.generate_slug(2)
    if connected?(socket), do: ChatWeb.Endpoint.subscribe(topic)

    socket =
      socket
      |> assign(room_id: room_id, topic: topic, username: username)
      # Инициализируем стрим с уникальным именем
      |> stream(:messages, [
        %{id: UUID.uuid4(), message: "#{username} joined in chat", username: "system"}
      ])

    {:ok, socket}
  end

  @impl true
  def handle_event("submit_message", %{"message" => message}, socket) do
    ChatWeb.Endpoint.broadcast(socket.assigns.topic, "new_message", %{
      id: UUID.uuid4(),
      message: message,
      username: socket.assigns.username
    })

    # Очищаем форму через JS-команду
    {:noreply, socket |> push_event("clear_form", %{selector: "#chat-form"})}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "new_message",
          payload: %{id: id, message: body, username: username}
        },
        socket
      ) do
    {:noreply, stream_insert(socket, :messages, %{id: id, message: body, username: username})}
  end
end
