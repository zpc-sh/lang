defmodule Lang.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :lang

  def migrate do
    load_app()

    if skip_db?() do
      IO.puts("SKIP_DB=1 set, skipping migrations")
    else
      for repo <- repos() do
        {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      end
    end
  end

  def rollback(repo, version) do
    load_app()
    if skip_db?() do
      IO.puts("SKIP_DB=1 set, skipping rollback")
    else
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp skip_db? do
    val = System.get_env("SKIP_DB") || "0"
    String.downcase(val) in ["1", "true", "yes", "on"]
  end
end
