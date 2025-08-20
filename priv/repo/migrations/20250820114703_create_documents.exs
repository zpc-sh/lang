defmodule Lang.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :content, :text, null: false
      add :format, :string, default: "markdown"
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps()
    end

    create index(:documents, [:user_id])
  end
end
