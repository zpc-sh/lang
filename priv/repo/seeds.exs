alias Nullity.CDFM.Adapters.Store.Ash, as: SpecStore
alias Lang.Workspace.Workspace

# Helper function to ensure repo is started
ensure_repo_started = fn ->
  case Process.whereis(Lang.Repo) do
    pid when is_pid(pid) ->
      :ok

    _ ->
      _ = Application.ensure_all_started(:logger)
      _ = Application.ensure_all_started(:ssl)
      _ = Application.ensure_all_started(:postgrex)

      case Lang.Repo.start_link() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        other -> IO.puts("Repo start error: #{inspect(other)}")
      end
  end
end

# Helper function to ingest LSP specs
ingest_specs_dir = fn dir ->
  IO.puts("Seeding LSP methods from #{dir} ...")

  files =
    ["**/*.jsonld", "**/*.yaml", "**/*.yml"]
    |> Enum.flat_map(&Path.wildcard(Path.join(dir, &1)))

  Enum.each(files, fn path ->
    case File.read(path) do
      {:ok, content} ->
        methods = Nullity.CDFM.Spec.parse_spec!(content)

        Enum.each(methods, fn s ->
          attrs = %{
            name: s.name,
            category: s.category,
            description: s.description,
            priority: s.priority,
            spec_status: s.spec_status,
            impl_file: s.impl_file,
            impl_module: s.impl_module,
            impl_function: s.impl_function && to_string(s.impl_function),
            impl_arity: s.impl_arity,
            params_schema: s.params_schema || %{},
            result_schema: s.result_schema || %{},
            links: s.links || %{},
            metadata: s.metadata || %{}
          }

          case SpecStore.upsert_method(attrs) do
            {:ok, _} -> :ok
            {:error, reason} -> IO.puts("Failed upsert #{s.name}: #{inspect(reason)}")
          end
        end)

      {:error, reason} ->
        IO.puts("Failed to read #{path}: #{inspect(reason)}")
    end
  end)
end

# Helper function to ensure default workspace exists
ensure_default_workspace = fn ->
  IO.puts("Ensuring default workspace ...")

  case Workspace |> Ash.Query.filter(project_id: "default") |> Ash.read() do
    {:ok, []} ->
      case Workspace
           |> Ash.Changeset.for_create(:create, %{
             name: "Default",
             project_id: "default",
             metadata: %{}
           })
           |> Ash.create() do
        {:ok, _} -> IO.puts("Created default workspace")
        {:error, reason} -> IO.puts("Failed to create default workspace: #{inspect(reason)}")
      end

    _ ->
      :ok
  end
end

# Execute seeding operations
ensure_repo_started.()
ingest_specs_dir.("priv/lsp/specs")
ensure_default_workspace.()
IO.puts("Seeds completed.")
