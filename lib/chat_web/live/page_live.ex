defmodule ChatWeb.PageLive do
  use ChatWeb, :live_view
  require Logger
  on_mount {ChatWeb.UserAuth, :require_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  # ✅ Обработка создания случайной комнаты
  @impl true
  def handle_event("random-room", _params, socket) do
    random_slug = "/" <> MnemonicSlugs.generate_slug(4)
    Logger.info("Creating random room: #{random_slug}")
    {:noreply, push_navigate(socket, to: random_slug)}
  end

  # ✅ Обработка ввода своей комнаты
  @impl true
  # ✅ Принимаем %{"id" => room_id} вместо %{"room" => %{"id" => room_id}}
  def handle_event("join_room", %{"id" => room_id}, socket) do
    clean_id = room_id |> String.trim() |> String.trim_leading("#")

    Logger.info("Joining room: #{clean_id}")

    {:noreply, push_navigate(socket, to: "/#{clean_id}")}
  end
end
