defmodule Lang.Repo.Migrations.CreateLspMethods do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

    create table(:lsp_methods, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :name, :string, null: false
      add :category, :string
      add :description, :string
      add :priority, :string
      add :spec_status, :string
      add :derived_status, :string
      add :impl_file, :string
      add :impl_module, :string
      add :impl_function, :string
      add :impl_arity, :integer
      add :params_schema, :map
      add :result_schema, :map
      add :links, :map
      add :metadata, :map

      timestamps()
    end

    create unique_index(:lsp_methods, [:name], name: :lsp_methods_unique_name)
  end
end

