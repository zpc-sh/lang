defmodule Lang.Repo.Migrations.AddIndexesToLspMethods do
  use Ecto.Migration

  def change do
    create index(:lsp_methods, [:category])
    create index(:lsp_methods, [:impl_file])
    create index(:lsp_methods, [:derived_status])
  end
end

