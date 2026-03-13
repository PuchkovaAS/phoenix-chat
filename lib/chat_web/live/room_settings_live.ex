# lib/chat_web/live/room_settings_live.ex
defmodule ChatWeb.RoomSettingsLive do
  @moduledoc """
  LiveView для настроек комнаты (только для создателя).
  """
  use ChatWeb, :live_view
  alias Chat.Rooms

  on_mount {ChatWeb.UserAuth, :require_authenticated}

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    room = Rooms.get_room_by_name(room_id) || Rooms.get_room!(room_id)
    user = socket.assigns.current_scope.user

    # 🔐 Только создатель может редактировать
    if room.creator_id != user.id do
      {:ok, push_navigate(socket, to: "/#{room_id}")}
    else
      {:ok,
       socket
       |> assign(:room, room)
       |> assign(:room_id, room_id)
       |> assign(:changeset, Rooms.Room.update_changeset(room, %{}))}
    end
  end

  @impl true
  def handle_event("update_room", %{"room" => attrs}, socket) do
    attrs = attrs |> Map.delete("password") |> Map.delete("confirm_password")

    case Rooms.update_room(socket.assigns.room, attrs) do
      {:ok, updated_room} ->
        {:noreply,
         socket
         |> assign(:room, updated_room)
         |> put_flash(:info, "Settings updated")
         |> push_patch(to: "/#{socket.assigns.room_id}/settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def handle_event(
        "update_password",
        %{"new_password" => new_pass, "confirm_password" => confirm_pass},
        socket
      ) do
    cond do
      new_pass == "" ->
        {:noreply, put_flash(socket, :error, "Password cannot be empty")}

      new_pass != confirm_pass ->
        {:noreply, put_flash(socket, :error, "Passwords do not match")}

      String.length(new_pass) < 6 ->
        {:noreply, put_flash(socket, :error, "Password must be at least 6 characters")}

      true ->
        case Rooms.update_room(socket.assigns.room, %{password: new_pass}) do
          {:ok, updated_room} ->
            {:noreply,
             socket
             |> assign(:room, updated_room)
             |> put_flash(:info, "Password updated")
             |> push_patch(to: "/#{socket.assigns.room_id}/settings")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update password")}
        end
    end
  end

  @impl true
  def handle_event("delete_room", _params, socket) do
    # 🔥 Удаление комнаты
    case Chat.Repo.delete(socket.assigns.room) do
      {:ok, _} ->
        {:noreply, push_navigate(socket, to: "/")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot delete room with messages")}
    end
  end
end
