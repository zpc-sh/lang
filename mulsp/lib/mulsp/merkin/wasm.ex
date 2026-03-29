defmodule Mulsp.Merkin.Wasm do
  @moduledoc """
  Bridge to the merkin Wasm module.

  Merkin stays MoonBit, compiles to Wasm, loaded here.
  Tree operations at Wasm speed, orchestration at Erlang speed.

  Strategy (in order of preference):
  1. Popcorn bridge (AtomVM ↔ Wasm) — when available
  2. Port-based: spawn merkin CLI binary, communicate over stdio
  3. Pure Erlang fallback: basic tree operations reimplemented

  For now, stub interface. Real Wasm bridge comes when Popcorn
  stabilizes or we build the port wrapper.
  """
  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    wasm_path = Path.join(:code.priv_dir(:mulsp), "merkin.wasm")

    state =
      if File.exists?(wasm_path) do
        Logger.info("[mulsp:merkin] found merkin.wasm at #{wasm_path}")
        %{mode: :wasm, path: wasm_path}
      else
        Logger.info("[mulsp:merkin] merkin.wasm not found, using stub mode")
        %{mode: :stub}
      end

    {:ok, state}
  end

  # --- Public API ---

  @doc "Build a sparse tree view filtered by routing tokens."
  def sparse_tree(tokens) when is_list(tokens) do
    GenServer.call(__MODULE__, {:sparse_tree, tokens})
  end

  @doc "Diff two sparse trees."
  def diff_trees(left_tokens, right_tokens) do
    GenServer.call(__MODULE__, {:diff_trees, left_tokens, right_tokens})
  end

  @doc "Check if a bloom sketch probably contains a token."
  def bloom_check(token) when is_binary(token) do
    GenServer.call(__MODULE__, {:bloom_check, token})
  end

  @doc "Ingest an envelope into the tree."
  def ingest(envelope_id, routing_tokens) do
    GenServer.call(__MODULE__, {:ingest, envelope_id, routing_tokens})
  end

  @doc "Seal the current epoch."
  def seal do
    GenServer.call(__MODULE__, :seal)
  end

  # --- Server callbacks ---

  @impl true
  def handle_call({:sparse_tree, _tokens}, _from, %{mode: :stub} = state) do
    {:reply, {:ok, %{nodes: 0, root: nil, mode: :stub}}, state}
  end

  def handle_call({:diff_trees, _left, _right}, _from, %{mode: :stub} = state) do
    {:reply, {:ok, %{added: [], removed: [], changed: [], unchanged: 0}}, state}
  end

  def handle_call({:bloom_check, _token}, _from, %{mode: :stub} = state) do
    {:reply, {:ok, false}, state}
  end

  def handle_call({:ingest, _id, _tokens}, _from, %{mode: :stub} = state) do
    {:reply, {:ok, :stub_ingested}, state}
  end

  def handle_call(:seal, _from, %{mode: :stub} = state) do
    {:reply, {:ok, :stub_sealed}, state}
  end

  # TODO: Wasm mode handlers via Popcorn or Port
end
