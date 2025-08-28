defmodule Nullity.CDFM.Adapters.Store.Ash do
  @moduledoc """
  Store adapter that persists specs to Ash (Lang.LSP.LspMethod).
  """
  @behaviour Nullity.CDFM.Adapters.Store

  alias Lang.LSP.LspMethod

  @impl true
  def upsert_method(method_map) when is_map(method_map) do
    attrs = %{
      name: method_map[:name] || method_map["name"],
      category: method_map[:category] || method_map["category"],
      description: method_map[:description] || method_map["description"],
      priority: method_map[:priority] || method_map["priority"],
      spec_status: method_map[:spec_status] || method_map["spec_status"],
      impl_file: method_map[:impl_file] || method_map["impl_file"],
      impl_module: method_map[:impl_module] || method_map["impl_module"],
      impl_function: to_string(method_map[:impl_function] || method_map["impl_function"] || "handle"),
      impl_arity: method_map[:impl_arity] || method_map["impl_arity"],
      params_schema: method_map[:params_schema] || method_map["params_schema"] || %{},
      result_schema: method_map[:result_schema] || method_map["result_schema"] || %{},
      links: method_map[:links] || method_map["links"] || %{},
      metadata: method_map[:metadata] || method_map["metadata"] || %{}
    }
    cond do
      ensure_repo_started() and function_exported?(LspMethod, :upsert, 1) ->
        case LspMethod.upsert(attrs) do
          {:ok, rec} -> {:ok, rec}
          {:error, reason} -> {:error, reason}
        end

      true ->
        {:ok, attrs}
    end
  end

  @impl true
  def read_all_methods do
    cond do
      ensure_repo_started() and function_exported?(LspMethod, :read_all, 0) ->
        case LspMethod.read_all() do
          {:ok, list} ->
            {:ok,
             Enum.map(list, fn m ->
               %{
                 name: m.name,
                 category: m.category,
                 description: m.description,
                 priority: m.priority,
                 spec_status: m.spec_status,
                 derived_status: m.derived_status,
                 impl_file: m.impl_file,
                 impl_module: m.impl_module,
                 impl_function: m.impl_function && String.to_atom(m.impl_function),
                 impl_arity: m.impl_arity,
                 params_schema: m.params_schema,
                 result_schema: m.result_schema,
                 links: m.links,
                 metadata: m.metadata
               }
             end)}
          _ -> read_all_from_specs_dir()
        end

      true ->
        read_all_from_specs_dir()
    end
  end

  @impl true
  def delete_method(name) when is_binary(name) do
    cond do
      ensure_repo_started() and function_exported?(LspMethod, :delete_by_name, 1) ->
        LspMethod.delete_by_name(name)
      true ->
        delete_method_from_specs(name)
    end
  end

  defp delete_method_from_specs(name, dir \\ "priv/lsp/specs") do
    files =
      ["**/*.jsonld", "**/*.yaml", "**/*.yml"]
      |> Enum.flat_map(fn pat -> Path.wildcard(Path.join(dir, pat)) end)

    case Enum.find(files, fn path -> file_contains_method?(path, name) end) do
      nil -> {:error, :not_found}
      path ->
        case File.rm(path) do
          :ok -> {:ok, :deleted}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp file_contains_method?(path, name) do
    case File.read(path) do
      {:ok, content} ->
        specs = Nullity.CDFM.Spec.parse_spec!(content)
        Enum.any?(specs, fn s -> s.name == name end)
      _ -> false
    end
  end

  defp ensure_repo_started do
    try do
      case Process.whereis(Lang.Repo) do
        pid when is_pid(pid) -> true
        _ ->
          # Start minimal dependencies needed for Repo
          _ = Application.ensure_all_started(:logger)
          _ = Application.ensure_all_started(:ssl)
          _ = Application.ensure_all_started(:postgrex)
          case Lang.Repo.start_link() do
            {:ok, _} -> true
            {:error, {:already_started, _}} -> true
            _ -> false
          end
      end
    rescue
      _ -> false
    end
  end

  defp read_all_from_specs_dir(dir \\ "priv/lsp/specs") do
    files =
      ["**/*.jsonld", "**/*.yaml", "**/*.yml"]
      |> Enum.flat_map(fn pat -> Path.wildcard(Path.join(dir, pat)) end)

    methods =
      files
      |> Enum.flat_map(fn path ->
        case File.read(path) do
          {:ok, content} -> Nullity.CDFM.Spec.parse_spec!(content)
          _ -> []
        end
      end)
      |> Enum.map(fn s ->
        derived =
          case (s.spec_status || "") |> to_string() |> String.downcase() do
            "implemented" -> :implemented
            "in_progress" -> :in_progress
            _ -> :not_started
          end

        %{
          name: s.name,
          category: s.category,
          description: s.description,
          priority: s.priority,
          spec_status: s.spec_status,
          derived_status: derived,
          impl_file: s.impl_file,
          impl_module: s.impl_module,
          impl_function: s.impl_function,
          impl_arity: s.impl_arity,
          params_schema: s.params_schema,
          result_schema: s.result_schema,
          links: s.links,
          metadata: s.metadata
        }
      end)

    {:ok, methods}
  end
end
