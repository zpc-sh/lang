defmodule Muyata.Substrate.Tree do
  @moduledoc """
  Merkin tree of learned knowledge — pure Elixir implementation.

  The tree represents everything muyata has learned:
  - Root = the void (empty at epoch 0)
  - Children = framing results, message types
  - Leaves = specific observed patterns (content-addressed)

  Content-addressed nodes using :crypto.hash. Compatible with the
  merkin MoonBit implementation's API shape.

  API mirrors Mulsp.Merkin.Wasm for interoperability.
  """
  use GenServer

  defmodule Node do
    @moduledoc false
    defstruct [:hash, :token, :children, :data, inserted_at: nil]
  end

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Ingest a pattern into the tree."
  def ingest(token, routing_tokens \\ []) when is_binary(token) do
    GenServer.cast(__MODULE__, {:ingest, token, routing_tokens})
  end

  @doc "Get a sparse tree view filtered by routing tokens."
  def sparse_tree(tokens \\ []) do
    GenServer.call(__MODULE__, {:sparse_tree, tokens})
  end

  @doc "Check if a token exists in the tree."
  def has_token?(token) do
    GenServer.call(__MODULE__, {:has_token, token})
  end

  @doc "Seal the current tree and return root hash."
  def seal do
    GenServer.call(__MODULE__, :seal)
  end

  @doc "Get tree statistics."
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @impl true
  def init(_opts) do
    state = %{
      nodes: %{},
      root_hash: nil,
      sealed_epochs: [],
      token_index: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:ingest, token, routing_tokens}, state) do
    hash = content_hash(token)
    now = System.system_time(:second)

    node = %Node{
      hash: hash,
      token: token,
      children: [],
      data: %{routing: routing_tokens},
      inserted_at: now
    }

    nodes = Map.put(state.nodes, hash, node)

    token_index =
      Enum.reduce([token | routing_tokens], state.token_index, fn t, idx ->
        Map.update(idx, t, [hash], &[hash | &1])
      end)

    root_hash = compute_root(nodes)

    {:noreply, %{state | nodes: nodes, root_hash: root_hash, token_index: token_index}}
  end

  @impl true
  def handle_call({:sparse_tree, []}, _from, state) do
    result = %{
      root: state.root_hash,
      nodes: map_size(state.nodes),
      tokens: Map.keys(state.token_index)
    }

    {:reply, {:ok, result}, state}
  end

  def handle_call({:sparse_tree, tokens}, _from, state) do
    matching =
      tokens
      |> Enum.flat_map(&Map.get(state.token_index, &1, []))
      |> Enum.uniq()

    result = %{
      root: state.root_hash,
      nodes: length(matching),
      matching_hashes: matching
    }

    {:reply, {:ok, result}, state}
  end

  def handle_call({:has_token, token}, _from, state) do
    {:reply, Map.has_key?(state.token_index, token), state}
  end

  def handle_call(:seal, _from, state) do
    epoch_snapshot = %{
      root_hash: state.root_hash,
      node_count: map_size(state.nodes),
      sealed_at: System.system_time(:second),
      tokens: Map.keys(state.token_index)
    }

    sealed = [epoch_snapshot | state.sealed_epochs]
    {:reply, {:ok, state.root_hash}, %{state | sealed_epochs: sealed}}
  end

  def handle_call(:stats, _from, state) do
    result = %{
      node_count: map_size(state.nodes),
      token_count: map_size(state.token_index),
      root_hash: state.root_hash,
      sealed_epochs: length(state.sealed_epochs)
    }

    {:reply, result, state}
  end

  defp content_hash(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  rescue
    _ -> Base.encode16(<<System.system_time(:nanosecond)::64>>, case: :lower)
  end

  defp compute_root(nodes) when map_size(nodes) == 0, do: nil

  defp compute_root(nodes) do
    nodes
    |> Map.keys()
    |> Enum.sort()
    |> Enum.join(":")
    |> content_hash()
  end
end
