defmodule Mulsp.Merkin.Wasm do
  @moduledoc """
  Bridge to the merkin wasm-gc module (MoonBit → wasm-gc → Elixir).

  Three execution modes, selected at startup:

  `:popcorn`  — AtomVM + Popcorn. Calls merkin.wasm-gc exports directly.
                The right long-term path. See WASM_BRIDGE.md §Path A.

  `:wasmex`   — Standard BEAM + wasmex NIF (Wasmtime). Requires `--target wasm`
                build of merkin. See WASM_BRIDGE.md §Path B.

  `:port`     — Spawn merkin native CLI binary as an Erlang port, communicate
                over stdio with a simple line protocol. Fallback; requires
                native binary (not AtomVM compatible). See WASM_BRIDGE.md §Path C.

  `:stub`     — No merkin available. bloom_check returns false (accept-all),
                tree ops return empty. Safe for development.

  Mode is selected by probing at startup:
    1. If `priv/merkin.wasm` exists and `:popcorn` module available → :popcorn
    2. If `priv/merkin.wasm` exists and `:wasmex` module available  → :wasmex
    3. If `priv/merkin`      exists (native binary)                 → :port
    4. Otherwise                                                    → :stub
  """
  use GenServer

  require Logger

  @wasm_path Path.join(:code.priv_dir(:mulsp), "merkin.wasm")
  @bin_path  Path.join(:code.priv_dir(:mulsp), "merkin")

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Add a routing token to the bloom sketch."
  def bloom_add(token) when is_binary(token) do
    GenServer.call(__MODULE__, {:bloom_add, token})
  end

  @doc """
  Check if a routing token might be in the bloom sketch.
  Returns {:ok, bool}. False positives possible; false negatives impossible.
  Returns {:ok, false} in stub mode (accept-all — conservative default).
  """
  def bloom_check(token) when is_binary(token) do
    GenServer.call(__MODULE__, {:bloom_check, token})
  end

  @doc "Serialize bloom sketch as hex string for DC wire transfer."
  def bloom_serialize do
    GenServer.call(__MODULE__, :bloom_serialize)
  end

  @doc """
  Ingest an envelope into the hot tree.
  routing_tokens: list of binary tokens, e.g. [\"security\", \"auth\"]
  Returns {:ok, root_hash} where root_hash is a hex string.
  """
  def ingest(envelope_id, routing_tokens) when is_binary(envelope_id) and is_list(routing_tokens) do
    GenServer.call(__MODULE__, {:ingest, envelope_id, routing_tokens})
  end

  @doc """
  Compute a sparse tree projection filtered by routing tokens.
  Returns {:ok, %{node_count: int, root: string | nil}}.
  """
  def sparse_tree(tokens) when is_list(tokens) do
    GenServer.call(__MODULE__, {:sparse_tree, tokens})
  end

  @doc "Seal the current epoch. Returns {:ok, root_hash} or {:ok, nil}."
  def seal do
    GenServer.call(__MODULE__, :seal)
  end

  @doc "Reset tree and bloom for session reuse."
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc "Current mode atom."
  def mode do
    GenServer.call(__MODULE__, :mode)
  end

  # --- Init ---

  @impl true
  def init(_opts) do
    mode = detect_mode()
    state = init_state(mode)
    Logger.info("[mulsp:merkin] mode=#{mode}")
    {:ok, state}
  end

  defp detect_mode do
    cond do
      wasm_exists?() and popcorn_available?() -> :popcorn
      wasm_exists?() and wasmex_available?()  -> :wasmex
      binary_exists?()                        -> :port
      true                                    -> :stub
    end
  end

  defp wasm_exists?,     do: File.exists?(@wasm_path)
  defp binary_exists?,   do: File.exists?(@bin_path)
  defp popcorn_available?, do: Code.ensure_loaded?(Popcorn)
  defp wasmex_available?,  do: Code.ensure_loaded?(Wasmex)

  defp init_state(:popcorn) do
    wasm = File.read!(@wasm_path)
    {:ok, instance} = Popcorn.load(wasm)
    %{mode: :popcorn, instance: instance}
  end

  defp init_state(:wasmex) do
    wasm = File.read!(@wasm_path)
    {:ok, store} = Wasmex.Store.new()
    {:ok, module} = Wasmex.Module.compile(store, wasm)
    {:ok, instance} = Wasmex.Instance.new(store, module, %{})
    %{mode: :wasmex, store: store, instance: instance}
  end

  defp init_state(:port) do
    port = Port.open({:spawn_executable, @bin_path}, [
      :binary, :use_stdio, {:line, 4096},
      args: ["daemon", "--action", "capabilities"]
    ])
    %{mode: :port, port: port, pending: %{}}
  end

  defp init_state(:stub) do
    %{mode: :stub}
  end

  # --- Dispatch ---

  @impl true
  def handle_call(:mode, _from, state), do: {:reply, state.mode, state}

  # Stub mode — everything is a no-op
  def handle_call({:bloom_add, _token}, _from, %{mode: :stub} = state),
    do: {:reply, :ok, state}

  def handle_call({:bloom_check, _token}, _from, %{mode: :stub} = state),
    do: {:reply, {:ok, false}, state}

  def handle_call(:bloom_serialize, _from, %{mode: :stub} = state),
    do: {:reply, {:ok, "256:" <> String.duplicate("0", 64)}, state}

  def handle_call({:ingest, _id, _tokens}, _from, %{mode: :stub} = state),
    do: {:reply, {:ok, :stub_root}, state}

  def handle_call({:sparse_tree, _tokens}, _from, %{mode: :stub} = state),
    do: {:reply, {:ok, %{node_count: 0, root: nil}}, state}

  def handle_call(:seal, _from, %{mode: :stub} = state),
    do: {:reply, {:ok, nil}, state}

  def handle_call(:reset, _from, %{mode: :stub} = state),
    do: {:reply, :ok, state}

  # Popcorn mode — direct wasm-gc calls via AtomVM
  def handle_call({:bloom_add, token}, _from, %{mode: :popcorn, instance: inst} = state) do
    result = safe_popcorn_call(inst, :bloom_add, [token])
    {:reply, result, state}
  end

  def handle_call({:bloom_check, token}, _from, %{mode: :popcorn, instance: inst} = state) do
    result = safe_popcorn_call(inst, :bloom_check, [token])
    {:reply, result, state}
  end

  def handle_call(:bloom_serialize, _from, %{mode: :popcorn, instance: inst} = state) do
    result = safe_popcorn_call(inst, :bloom_serialize, [])
    {:reply, result, state}
  end

  def handle_call({:ingest, id, tokens}, _from, %{mode: :popcorn, instance: inst} = state) do
    csv = Enum.join(tokens, ",")
    result = safe_popcorn_call(inst, :tree_ingest, [id, csv])
    {:reply, result, state}
  end

  def handle_call({:sparse_tree, tokens}, _from, %{mode: :popcorn, instance: inst} = state) do
    csv = Enum.join(tokens, ",")
    {:ok, raw} = safe_popcorn_call(inst, :tree_sparse, [csv])
    {:reply, {:ok, parse_kv(raw)}, state}
  end

  def handle_call(:seal, _from, %{mode: :popcorn, instance: inst} = state) do
    result = safe_popcorn_call(inst, :tree_seal, [])
    {:reply, result, state}
  end

  def handle_call(:reset, _from, %{mode: :popcorn, instance: inst} = state) do
    safe_popcorn_call(inst, :reset, [])
    {:reply, :ok, state}
  end

  # wasmex mode — Wasmtime NIF on standard BEAM
  def handle_call({:bloom_add, token}, _from, %{mode: :wasmex} = state) do
    result = safe_wasmex_call(state, "bloom_add", [token])
    {:reply, result, state}
  end

  def handle_call({:bloom_check, token}, _from, %{mode: :wasmex} = state) do
    case safe_wasmex_call(state, "bloom_check", [token]) do
      {:ok, [1 | _]} -> {:reply, {:ok, true}, state}
      {:ok, _}       -> {:reply, {:ok, false}, state}
      err            -> {:reply, err, state}
    end
  end

  def handle_call(:bloom_serialize, _from, %{mode: :wasmex} = state) do
    result = safe_wasmex_call(state, "bloom_serialize", [])
    {:reply, result, state}
  end

  def handle_call({:ingest, id, tokens}, _from, %{mode: :wasmex} = state) do
    csv = Enum.join(tokens, ",")
    result = safe_wasmex_call(state, "tree_ingest", [id, csv])
    {:reply, result, state}
  end

  def handle_call({:sparse_tree, tokens}, _from, %{mode: :wasmex} = state) do
    csv = Enum.join(tokens, ",")
    case safe_wasmex_call(state, "tree_sparse", [csv]) do
      {:ok, [raw]} -> {:reply, {:ok, parse_kv(raw)}, state}
      err          -> {:reply, err, state}
    end
  end

  def handle_call(:seal, _from, %{mode: :wasmex} = state) do
    result = safe_wasmex_call(state, "tree_seal", [])
    {:reply, result, state}
  end

  def handle_call(:reset, _from, %{mode: :wasmex} = state) do
    safe_wasmex_call(state, "reset", [])
    {:reply, :ok, state}
  end

  # Port mode — native CLI binary over stdio
  def handle_call({:bloom_check, token}, _from, %{mode: :port, port: port} = state) do
    result = port_call(port, "bloom_check #{token}")
    {:reply, result, state}
  end

  def handle_call({:bloom_add, token}, _from, %{mode: :port, port: port} = state) do
    port_cast(port, "bloom_add #{token}")
    {:reply, :ok, state}
  end

  def handle_call(:bloom_serialize, _from, %{mode: :port, port: port} = state) do
    result = port_call(port, "bloom_serialize")
    {:reply, result, state}
  end

  def handle_call({:ingest, id, tokens}, _from, %{mode: :port, port: port} = state) do
    csv = Enum.join(tokens, ",")
    result = port_call(port, "ingest #{id} #{csv}")
    {:reply, result, state}
  end

  def handle_call({:sparse_tree, tokens}, _from, %{mode: :port, port: port} = state) do
    csv = Enum.join(tokens, ",")
    case port_call(port, "sparse #{csv}") do
      {:ok, raw} -> {:reply, {:ok, parse_kv(raw)}, state}
      err        -> {:reply, err, state}
    end
  end

  def handle_call(:seal, _from, %{mode: :port, port: port} = state) do
    result = port_call(port, "seal")
    {:reply, result, state}
  end

  def handle_call(:reset, _from, %{mode: :port, port: port} = state) do
    port_cast(port, "reset")
    {:reply, :ok, state}
  end

  # --- Port helpers ---

  defp port_call(port, command) do
    Port.command(port, command <> "\n")

    receive do
      {^port, {:data, {:eol, line}}} ->
        {:ok, line}

      {^port, {:exit_status, code}} ->
        {:error, {:port_exit, code}}
    after
      5_000 -> {:error, :port_timeout}
    end
  end

  defp port_cast(port, command) do
    Port.command(port, command <> "\n")
  end

  # --- Popcorn helpers ---

  defp safe_popcorn_call(instance, func, args) do
    {:ok, Popcorn.call(instance, func, args)}
  rescue
    e -> {:error, {:popcorn, Exception.message(e)}}
  end

  # --- wasmex helpers ---

  defp safe_wasmex_call(%{store: store, instance: instance}, func, args) do
    Wasmex.call_function(store, instance, func, args)
  rescue
    e -> {:error, {:wasmex, Exception.message(e)}}
  end

  # --- Parse merkin's k=v line format ---

  defp parse_kv(raw) when is_binary(raw) do
    raw
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, "=", parts: 2) do
        [k, v] -> {String.to_atom(k), parse_value(v)}
        _      -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp parse_value("none"), do: nil
  defp parse_value(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _       -> v
    end
  end
end
