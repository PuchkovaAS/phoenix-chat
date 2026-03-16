defmodule Chat.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  # Важно: замените на атом имени вашего приложения (из mix.exs)
  @app :chat

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
