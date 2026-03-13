defmodule Chat.Messages do
  @moduledoc """
  Контекст для работы с сообщениями.
  """

  import Ecto.Query
  alias Chat.Repo
  alias Chat.Messages.Message
  alias Chat.Accounts.User
  alias Chat.Accounts.UserRoomReadState

  require Logger

  def create_message(%User{} = user, attrs) do
    user
    |> Ecto.build_assoc(:messages)
    |> Message.create_changeset(attrs)
    |> Repo.insert()
  end

  def get_message!(id) do
    Repo.get!(Message, id)
    |> Message.decrypt_content()
  end

  def delete_message(%Message{} = message) do
    message
    |> Message.update_changeset(%{deleted_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def edit_message(%Message{} = message, new_content) do
    %{ciphertext: ct, iv: iv, tag: tag} = Chat.Crypto.MessageEncryptor.encrypt(new_content)

    message
    |> Message.update_changeset(%{
      content_encrypted: ct,
      iv: iv,
      auth_tag: tag,
      edited_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  def cleanup_expired_messages do
    now = DateTime.utc_now()

    from(m in Message,
      where: not is_nil(m.expires_at) and m.expires_at < ^now
    )
    |> Repo.delete_all()
  end

  def count_room_messages(room_id) do
    from(m in Message,
      where: m.room_id == ^room_id and is_nil(m.deleted_at)
    )
    |> Repo.aggregate(:count, :id) || 0
  end

  def list_room_messages(room_id, limit \\ 50, cursor \\ nil, user_id \\ nil) do
    base_query =
      from m in Message,
        where: m.room_id == ^room_id and is_nil(m.deleted_at),
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        preload: [:user]

    query =
      if cursor do
        from m in base_query, where: m.inserted_at < ^cursor
      else
        base_query
      end

    messages =
      query
      |> Repo.all()
      |> Enum.map(&Message.decrypt_content/1)
      |> Enum.reverse()

    read_state = if user_id, do: get_read_state(user_id, room_id), else: nil

    messages
    |> enumerate_with_headers()
    |> Enum.map(&message_to_map(&1, read_state))
  end

  def get_read_state(user_id, room_id) do
    Repo.get_by(UserRoomReadState, user_id: user_id, room_id: room_id)
  end

  def update_read_state(user_id, room_id, last_message_id) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    case Repo.get_by(UserRoomReadState, user_id: user_id, room_id: room_id) do
      nil ->
        %UserRoomReadState{
          user_id: user_id,
          room_id: room_id,
          last_read_message_id: last_message_id,
          unread_count: 0,
          last_seen_at: now
        }
        |> UserRoomReadState.changeset(%{})
        |> Repo.insert()

      read_state ->
        read_state
        |> UserRoomReadState.changeset(%{
          last_read_message_id: last_message_id,
          unread_count: 0,
          last_seen_at: now
        })
        |> Repo.update()
    end
  end

  def count_unread_messages(user_id, room_id) do
    read_state = get_read_state(user_id, room_id)

    base_query =
      from m in Message,
        where: m.room_id == ^room_id and is_nil(m.deleted_at)

    query =
      if read_state && read_state.last_seen_at do
        from m in base_query,
          where: m.inserted_at > ^read_state.last_seen_at
      else
        base_query
      end

    Repo.aggregate(query, :count, :id) || 0
  end

  defp enumerate_with_headers(messages) do
    Enum.reduce(messages, {[], nil, nil}, fn message, {acc, last_user, last_time} ->
      current_user = get_username(message)
      current_time = message.inserted_at

      show_header =
        cond do
          is_nil(last_user) -> true
          last_user != current_user -> true
          !is_nil(last_time) && DateTime.diff(current_time, last_time, :second) > 300 -> true
          true -> false
        end

      {[{message, show_header} | acc], current_user, current_time}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp message_to_map({%Message{} = message, show_header}, read_state \\ nil) do
    username = get_username(message)

    is_read =
      case read_state do
        nil ->
          false

        %{} ->
          !is_nil(read_state.last_seen_at) &&
            DateTime.compare(message.inserted_at, read_state.last_seen_at) != :gt
      end

    # 🔍 Отладка
    IO.inspect(
      %{
        id: message.id,
        inserted_at: message.inserted_at,
        last_seen_at: read_state && read_state.last_seen_at,
        is_read: is_read
      },
      label: "MESSAGE MAP"
    )

    %{
      id: to_string(message.id || ""),
      message: message.content || "",
      username: username || "anonymous",
      timestamp: DateTime.to_iso8601(message.inserted_at || DateTime.utc_now()),
      show_header: show_header || false,
      is_read: is_read || false
    }
  end

  defp get_username(%Message{user: nil}), do: "anonymous"

  defp get_username(%Message{user: user}) do
    cond do
      user && user.nickname && user.nickname != "" -> user.nickname
      true -> "anonymous"
    end
  end
end
