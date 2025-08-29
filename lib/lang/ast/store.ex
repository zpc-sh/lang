defmodule Lang.AST.Store do
  @moduledoc """
  ETS-backed store for per-document AST snapshots, keyed by {uri, version} and
  a convenience key {uri, :latest} -> version.

  This is a simple, low-latency cache to enable LSP features to reuse parsed
  state across requests. It is intentionally minimal for an initial spine.
  """

  use GenServer
  alias Lang.AST.Snapshot

  @table :lang_ast_store

  # --- Client API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec put(Snapshot.t()) :: :ok
  def put(%Snapshot{uri: uri, version: ver} = snap) do
    :ets.insert(@table, {{uri, ver}, snap})
    :ets.insert(@table, {{uri, :latest}, ver})
    :ok
  end

  @spec get(String.t(), non_neg_integer() | :latest) :: Snapshot.t() | nil
  def get(uri, version_or_latest \\ :latest) do
    ver =
      case version_or_latest do
        :latest ->
          case :ets.lookup(@table, {uri, :latest}) do
            [{{^uri, :latest}, v}] -> v
            _ -> nil
          end

        v when is_integer(v) ->
          v
      end

    if ver do
      case :ets.lookup(@table, {uri, ver}) do
        [{{^uri, ^ver}, snap}] -> snap
        _ -> nil
      end
    else
      nil
    end
  end

  @spec delete_uri(String.t()) :: :ok
  def delete_uri(uri) do
    # Delete latest pointer
    :ets.delete(@table, {uri, :latest})
    # Brute-force delete all versions for URI (scan small table)
    match_spec = [{{{uri, :"$1"}, :"$2"}, [], [true]}]
    :ets.select_delete(@table, match_spec)
    :ok
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end
end
