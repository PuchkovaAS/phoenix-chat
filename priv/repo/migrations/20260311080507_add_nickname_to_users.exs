defmodule Chat.Repo.Migrations.AddNicknameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :nickname, :string
    end

    create unique_index(:users, [:nickname])
  end
end
