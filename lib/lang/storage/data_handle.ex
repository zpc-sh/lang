defmodule Lang.Storage.DataHandle do
  @moduledoc """
  Resolves logical storage handles to runtime adapter chains with policy-driven
  remapping/failover semantics.
  """

  require Logger

  @type chain_entry :: %{backend: atom(), adapter: module(), path: String.t(), available?: (() -> boolean())}

  @spec resolve(String.t(), map()) :: map()
  def resolve(logical_handle, ctx \\ %{}) when is_binary(logical_handle) and is_map(ctx) do
    policy = policy(ctx)
    remap = Map.get(policy, :remap, %{})
    resolved_handle = Map.get(remap, logical_handle, logical_handle)

    chain =
      resolved_handle
      |> chain_for_handle()
      |> apply_policy(policy)

    %{
      logical_handle: logical_handle,
      resolved_handle: resolved_handle,
      chain: chain,
      resolved_backend_path: backend_path(chain),
      failover?: Map.get(policy, :failover, true)
    }
  end

  @spec execute(String.t(), String.t(), (chain_entry() -> {:ok, any()} | {:error, any()}), map()) ::
          {:ok, any()} | {:error, any()}
  def execute(logical_handle, operation, executor, ctx \\ %{})
      when is_binary(logical_handle) and is_binary(operation) and is_function(executor, 1) and is_map(ctx) do
    resolution = resolve(logical_handle, ctx)

    Logger.metadata(
      data_handle: resolution.logical_handle,
      data_backend_path: resolution.resolved_backend_path,
      data_operation: operation
    )

    do_execute(resolution, operation, executor, [])
  end

  defp do_execute(%{chain: []} = resolution, operation, _executor, errors) do
    log_resolution(:error, resolution, operation, :no_adapter_available, errors)
    {:error, {:no_adapter_available, meta(resolution, nil, errors)}}
  end

  defp do_execute(resolution, operation, executor, errors) do
    [entry | rest] = resolution.chain

    case executor.(entry) do
      {:ok, payload} ->
        log_resolution(:info, resolution, operation, {:ok, entry.backend}, errors)
        {:ok, enrich_success_payload(payload, resolution, entry)}

      {:error, reason} ->
        updated_errors = errors ++ [%{backend: entry.backend, reason: reason}]
        log_resolution(:warning, resolution, operation, {:error, entry.backend}, updated_errors)

        cond do
          rest == [] or resolution.failover? == false ->
            {:error, decorate_error(reason, resolution, entry, updated_errors)}

          true ->
            do_execute(%{resolution | chain: rest}, operation, executor, updated_errors)
        end

      other ->
        updated_errors = errors ++ [%{backend: entry.backend, reason: {:unexpected_return, other}}]
        log_resolution(:warning, resolution, operation, {:unexpected, entry.backend}, updated_errors)

        if rest == [] do
          {:error, {:unexpected_return, meta(resolution, entry, updated_errors)}}
        else
          do_execute(%{resolution | chain: rest}, operation, executor, updated_errors)
        end
    end
  end

  defp decorate_error({code, message}, resolution, _entry, _errors)
       when is_integer(code) and is_binary(message) do
    {code, "#{message} [handle=#{resolution.logical_handle} path=#{resolution.resolved_backend_path}]"}
  end

  defp decorate_error({:error, code, message}, resolution, _entry, _errors)
       when is_integer(code) and is_binary(message) do
    {:error, code,
     "#{message} [handle=#{resolution.logical_handle} path=#{resolution.resolved_backend_path}]"}
  end

  defp decorate_error(reason, resolution, entry, errors) do
    {:resolution_failed, reason, meta(resolution, entry, errors)}
  end

  defp enrich_success_payload(payload, resolution, entry) when is_map(payload) do
    Map.put(payload, :_data_handle, meta(resolution, entry, []))
  end

  defp enrich_success_payload(payload, resolution, entry) do
    %{result: payload, _data_handle: meta(resolution, entry, [])}
  end

  defp meta(resolution, entry, errors) do
    %{
      logical_handle: resolution.logical_handle,
      resolved_handle: resolution.resolved_handle,
      resolved_backend: entry && entry.backend,
      resolved_backend_path: resolution.resolved_backend_path,
      errors: errors
    }
  end

  defp backend_path([]), do: "none"

  defp backend_path(chain) do
    chain
    |> Enum.map(& &1.path)
    |> Enum.join(" -> ")
  end

  defp log_resolution(level, resolution, operation, status, errors) do
    msg =
      "data_handle op=#{operation} status=#{inspect(status)} logical=#{resolution.logical_handle} " <>
        "path=#{resolution.resolved_backend_path} errors=#{length(errors)}"

    case level do
      :info -> Logger.info(msg)
      :warning -> Logger.warning(msg)
      :error -> Logger.error(msg)
    end
  end

  defp policy(ctx) do
    global = Application.get_env(:lang, :storage_data_handle_policy, %{})
    runtime = Map.get(ctx, :data_handle_policy, %{})
    Map.merge(global, runtime)
  end

  defp apply_policy(chain, policy) do
    disabled = Map.get(policy, :disable_backends, []) |> MapSet.new()

    chain =
      chain
      |> Enum.filter(fn entry ->
        entry.available?.() and not MapSet.member?(disabled, entry.backend)
      end)

    case Map.get(policy, :prefer_backends, []) do
      [] -> chain
      preferred -> reorder_chain(chain, preferred)
    end
  end

  defp reorder_chain(chain, preferred) do
    rank = preferred |> Enum.with_index() |> Map.new()

    Enum.sort_by(chain, fn entry -> Map.get(rank, entry.backend, 9_999) end)
  end

  defp chain_for_handle(handle) do
    handles =
      Application.get_env(:lang, :storage_data_handles, %{})
      |> normalize_handle_config()

    Map.get(handles, handle, default_handle_chains()[handle] || [])
  end

  defp normalize_handle_config(config) do
    Enum.into(config, %{}, fn {k, chain} -> {to_string(k), normalize_chain(chain)} end)
  end

  defp normalize_chain(chain) do
    Enum.map(chain, fn entry ->
      %{
        backend: Map.fetch!(entry, :backend),
        adapter: Map.fetch!(entry, :adapter),
        path: Map.get(entry, :path, Atom.to_string(Map.fetch!(entry, :backend))),
        available?: Map.get(entry, :available?, fn -> true end)
      }
    end)
  end

  defp default_handle_chains do
    %{
      "patterns" =>
        normalize_chain([
          %{backend: :folder, adapter: Lang.Storage.Folder, path: "folder.patterns", available?: &dirup_enabled?/0},
          %{backend: :pg, adapter: Lang.Storage.PatternStore, path: "pg.pattern_store"},
          %{backend: :mysql, adapter: Lang.Storage.PatternStore, path: "mysql.pattern_store"},
          %{backend: :csv, adapter: Lang.Storage.PatternStore, path: "csv.pattern_store"},
          %{backend: :merkin, adapter: Lang.Storage.PatternStore, path: "merkin.pattern_store"}
        ]),
      "user_context" =>
        normalize_chain([
          %{backend: :folder, adapter: Lang.Storage.Folder, path: "folder.user_context", available?: &dirup_enabled?/0},
          %{backend: :pg, adapter: Lang.InMemory.Store, path: "pg.user_context_cache"},
          %{backend: :mysql, adapter: Lang.InMemory.Store, path: "mysql.user_context_cache"},
          %{backend: :csv, adapter: Lang.InMemory.Store, path: "csv.user_context_cache"},
          %{backend: :merkin, adapter: Lang.InMemory.Store, path: "merkin.user_context_cache"}
        ])
    }
  end

  defp dirup_enabled? do
    val = System.get_env("FOLDER_ENABLED") || System.get_env("LANG_FOLDER_ENABLED") || "0"
    String.downcase(val) in ["1", "true", "yes", "on"]
  end
end
