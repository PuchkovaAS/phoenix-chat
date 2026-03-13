defmodule Chat.Messages do
  @moduledoc """
  Контекст для работы с сообщениями.
  """

  import Ecto.Query
  alias Chat.Repo
  alias Chat.Messages.Message
  alias Chat.Accounts.User

  require Logger

  def create_message(%User{} = user, attrs) do
    user
    |> Ecto.build_assoc(:messages)
    |> Message.create_changeset(attrs)
    |> Repo.insert()
  end

  # ✅ ИСПРАВЛЕНО: Заголовок функции с дефолтными значениями вынесен наверх

  def list_room_messages(room_id, limit \\ 50, before_id \\ nil) do
    query =
      from m in Message,
        where: m.room_id == ^room_id and is_nil(m.deleted_at),
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        preload: [:user]

    query =
      if before_id do
        from m in query, where: m.id < ^before_id
      else
        query
      end

    messages =
      query
      |> Repo.all()
      |> Repo.preload(:user)
      |> Enum.map(&Message.decrypt_content/1)
      |> Enum.reverse()

    # 🔍 УЛУЧШЕННАЯ ОТЛАДКА
    Logger.debug("=== MESSAGES DEBUG ===")
    Logger.debug("Total messages: #{length(messages)}")

    Enum.each(messages, fn msg ->
      Logger.debug("""
      --- Message #{msg.id} ---
      User loaded?: #{if msg.user, do: "YES", else: "NO"}
      User struct: #{inspect(msg.user, limit: :infinity, structs: false)}
      Nickname value: #{if msg.user, do: inspect(msg.user.nickname), else: "N/A"}
      Extracted username: #{get_username(msg)}
      """)
    end)

    Logger.debug("=== END DEBUG ===")

    enumerate_with_headers(messages)
    |> Enum.map(&message_to_map/1)
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
    %{ciphertext: ct, iv: iv, tag: tag} = MessageEncryptor.encrypt(new_content)

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
    |> Repo.aggregate(:count, :id)
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

  defp message_to_map({%Message{} = message, show_header}) do
    username = get_username(message)

    %{
      id: to_string(message.id),
      message: message.content,
      username: username,
      timestamp: DateTime.to_iso8601(message.inserted_at),
      show_header: show_header
    }
  end

  defp get_username(%Message{user: nil}), do: "anonymous"

  defp get_username(%Message{user: user}) do
    cond do
      user.nickname && user.nickname != "" -> user.nickname
      true -> "anonymous"
    end
  end
end
