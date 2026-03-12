defmodule Lang.Repo.Migrations.CreateLspMethods do
  use Ecto.Migration

  def change do
    create table(:lsp_methods, primary_key: false) do
      add :id, :uuid, primary_key: true
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
      add :params_schema, :map, null: false, default: %{}
      add :result_schema, :map, null: false, default: %{}
      add :links, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:lsp_methods, [:name], name: :lsp_methods_unique_name)
  end
end

