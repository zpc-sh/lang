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

  @doc "Seed LSP specs idempotently based on configuration"
  def seed_specs do
    load_app()

    cfg = Application.get_env(@app, :lsp_specs, [])
    mode = to_string(Keyword.get(cfg, :mode, System.get_env("LANG_SPECS_STORE") || "db"))
    import_mode = to_string(Keyword.get(cfg, :import, System.get_env("LANG_SPECS_IMPORT") || "changed"))
    dir = Keyword.get(cfg, :dir, System.get_env("LANG_SPECS_DIR") || "priv/lsp/specs")

    if import_mode == "never" do
      IO.puts("[seed_specs] import disabled (LANG_SPECS_IMPORT=never)")
      :ok
    else
      case mode do
        "db" -> seed_specs_db(dir)
        _ ->
          IO.puts("[seed_specs] mode=fs — no DB writes; using specs from #{dir}")
          :ok
      end
    end
  end

  defp seed_specs_db(dir) do
    if skip_db?() do
      IO.puts("[seed_specs] SKIP_DB=1 set, skipping DB import")
      :ok
    else
      # Ensure Repo is available for upserts
      _ = Application.ensure_all_started(:logger)
      _ = Application.ensure_all_started(:ssl)
      _ = Application.ensure_all_started(:postgrex)
      case Lang.Repo.start_link() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        other -> IO.puts("[seed_specs] Repo start: #{inspect(other)}")
      end

      lock_key = :erlang.phash2("lang_lsp_seed_specs", 4_294_967_295)
      locked? =
        case Ecto.Adapters.SQL.query(Lang.Repo, "select pg_try_advisory_lock($1)", [lock_key]) do
          {:ok, %{rows: [[true]]}} -> true
          _ -> false
        end

      if not locked? do
        IO.puts("[seed_specs] another node holds the seed lock; skipping")
        :ok
      else
        try do
          do_seed_specs(dir)
        after
          _ = Ecto.Adapters.SQL.query(Lang.Repo, "select pg_advisory_unlock($1)", [lock_key])
        end
      end
    end
  end

  defp do_seed_specs(dir) do
    alias Lang.Native.FSScanner
    alias Nullity.CDFM.Spec
    alias Nullity.CDFM.Adapters.Store.Ash, as: SpecStore
    alias Nullity.CDFM.Adapters.FileAdapter.FSScanner, as: FileAdapter

    IO.puts("[seed_specs] scanning #{dir} for specs …")

    files =
      case FSScanner.search(dir, ~S/\.(jsonld|ya?ml)$/, max_results: 50_000) do
        {:ok, results} when is_list(results) ->
          Enum.map(results, fn
            %{:path => path} -> path
            %{"path" => path} -> path
            path when is_binary(path) -> path
          end)
        _ -> []
      end

    {ok, err} =
      Enum.reduce(files, {0, 0}, fn path, {okc, errc} ->
        case FileAdapter.read(path) do
          {:ok, content} ->
            specs = Spec.parse_jsonld!(content)
            Enum.reduce(specs, {okc, errc}, fn s, {o, e} ->
              attrs = %{
                name: s.name,
                category: s.category,
                description: s.description,
                priority: s.priority,
                spec_status: s.spec_status,
                impl_file: s.impl_file,
                impl_module: s.impl_module,
                impl_function: s.impl_function,
                impl_arity: s.impl_arity,
                params_schema: s.params_schema,
                result_schema: s.result_schema,
                links: s.links,
                metadata: s.metadata
              }

              case SpecStore.upsert_method(attrs) do
                {:ok, _} -> {o + 1, e}
                {:error, reason} ->
                  IO.puts("[seed_specs] upsert failed #{s.name}: #{inspect(reason)}")
                  {o, e + 1}
              end
            end)

          {:error, reason} ->
            IO.puts("[seed_specs] read failed #{path}: #{inspect(reason)}")
            {okc, errc + 1}
        end
      end)

    IO.puts("[seed_specs] done. upserts=#{ok} errors=#{err}")
    :ok
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
