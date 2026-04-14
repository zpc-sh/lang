defmodule Lang.Mulsp.Birthing do
  @moduledoc """
  Spawns and deploys mulsp/muyata instances from Lang.

  Two deployment modes:

  `:beam` — Spawn as a supervised child process on this BEAM node.
    Fast, zero-latency. The spawned mulsp runs in the same VM, gets
    its partition via init args, and registers back to Lang.Mulsp.Registry.

  `:atomvm` — Emit a packbeam `.avm` binary (pre-built) with the
    partition config injected as a priv-file payload. Drop the `.avm`
    to the target (TFTP, DC protocol, direct copy). The AtomVM
    instance reads its partition from the injected priv file on boot.

  Context-sensitive deployment: Lang decides which context based on the
  active AI session — what the AI is doing determines the partition DNA.
  """

  require Logger

  @mulsp_avm_path Application.compile_env(:lang, [:mulsp, :avm_path],
    Path.join(:code.priv_dir(:lang), "mulsp.avm")
  )
  @muyata_avm_path Application.compile_env(:lang, [:mulsp, :muyata_avm_path],
    Path.join(:code.priv_dir(:lang), "muyata.avm")
  )

  @doc """
  Spawn a mulsp instance for the given AI context.

  Options:
  - `:mode` — `:beam` (default) or `:atomvm`
  - `:base_port` — base port for this instance's protocol suite
  - `:lang_host` — host where Lang is reachable from the spawned instance
  - `:lang_port` — port for Lang's control channel
  - `:target` — for `:atomvm` mode, `{host, port}` of the AtomVM node
  """
  def spawn(context, opts \\ []) do
    mode = Keyword.get(opts, :mode, :beam)
    partition = Lang.Mulsp.Partition.for_context(context, opts)
    node_id = generate_node_id(partition.role)
    partition = %{partition | node_id: node_id}

    case mode do
      :beam -> spawn_beam(:mulsp, node_id, partition, opts)
      :atomvm -> deploy_atomvm(:mulsp, node_id, partition, opts)
    end
  end

  @doc "Spawn a muyata observer instance."
  def spawn_muyata(opts \\ []) do
    mode = Keyword.get(opts, :mode, :beam)
    node_id = generate_node_id(:observer)

    config = %{
      node_id: node_id,
      listen_port: Keyword.get(opts, :listen_port, 5432),
      upstream_host: Keyword.get(opts, :upstream_host, "127.0.0.1"),
      upstream_port: Keyword.get(opts, :upstream_port, 5433),
      gopher_port: Keyword.get(opts, :gopher_port, 7170),
      finger_port: Keyword.get(opts, :finger_port, 7179),
      dc_port: Keyword.get(opts, :dc_port, 7171)
    }

    case mode do
      :beam -> spawn_beam(:muyata, node_id, config, opts)
      :atomvm -> deploy_atomvm(:muyata, node_id, config, opts)
    end
  end

  @doc """
  Generate an `.avm` binary with the partition config injected.

  Returns `{:ok, avm_binary}` or `{:error, reason}`.
  The binary can be dropped to an AtomVM node via TFTP, DC, or file.
  """
  def packbeam(:mulsp, partition) do
    with {:ok, base_avm} <- read_avm(@mulsp_avm_path),
         config_binary = Lang.Mulsp.Partition.to_atomvm_config(partition),
         {:ok, patched} <- inject_config(base_avm, config_binary) do
      {:ok, patched}
    end
  end

  def packbeam(:muyata, config) do
    with {:ok, base_avm} <- read_avm(@muyata_avm_path),
         config_binary = :erlang.term_to_binary(config),
         {:ok, patched} <- inject_config(base_avm, config_binary) do
      {:ok, patched}
    end
  end

  # --- BEAM mode ---

  defp spawn_beam(kind, node_id, config, _opts) do
    supervisor = Lang.Mulsp.InstanceSupervisor

    child_spec = %{
      id: node_id,
      start: {Lang.Mulsp.Instance, :start_link, [[kind: kind, node_id: node_id, config: config]]},
      restart: :transient,
      type: :worker
    }

    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} ->
        entry = %{
          kind: kind,
          node_id: node_id,
          pid: pid,
          role: Map.get(config, :role, :generic),
          mode: :beam,
          control_port: Map.get(config, :control_port),
          partition: config,
          spawned_at: System.system_time(:second)
        }

        Lang.Mulsp.Registry.register(node_id, entry)
        Logger.info("[Lang.Mulsp.Birthing] spawned #{kind} #{node_id} as BEAM child pid=#{inspect(pid)}")
        {:ok, node_id, pid}

      {:error, reason} ->
        Logger.error("[Lang.Mulsp.Birthing] failed to spawn #{kind}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- AtomVM mode ---

  defp deploy_atomvm(kind, node_id, config, opts) do
    target = Keyword.get(opts, :target)

    case packbeam(kind, config) do
      {:ok, avm_binary} ->
        result =
          if target do
            drop_via_tftp(avm_binary, target)
          else
            {:ok, avm_binary}
          end

        case result do
          {:ok, _} ->
            entry = %{
              kind: kind,
              node_id: node_id,
              pid: nil,
              role: Map.get(config, :role, :generic),
              mode: :atomvm,
              control_port: nil,
              partition: config,
              target: target,
              spawned_at: System.system_time(:second)
            }

            Lang.Mulsp.Registry.register(node_id, entry)
            Logger.info("[Lang.Mulsp.Birthing] deployed #{kind} #{node_id} as AtomVM target=#{inspect(target)}")
            {:ok, node_id, avm_binary}

          {:error, _} = err ->
            err
        end

      {:error, reason} ->
        {:error, {:packbeam_failed, reason}}
    end
  end

  # Drop `.avm` to AtomVM node via TFTP (RFC 1350, UDP port 69).
  # Lightweight — no handshake, just WRQ + data blocks.
  defp drop_via_tftp(avm_binary, {host, port}) do
    filename = "mulsp.avm"
    host_charlist = if is_binary(host), do: to_charlist(host), else: host

    case :gen_udp.open(0, [:binary]) do
      {:ok, sock} ->
        # TFTP WRQ packet: opcode=2, filename\0, mode\0
        wrq = <<0, 2, filename::binary, 0, "octet", 0>>
        :gen_udp.send(sock, host_charlist, port, wrq)

        result = tftp_send_blocks(sock, host_charlist, port, avm_binary, 1)
        :gen_udp.close(sock)
        result

      {:error, reason} ->
        {:error, {:udp_open_failed, reason}}
    end
  end

  defp tftp_send_blocks(_sock, _host, _port, <<>>, _block_num), do: {:ok, :sent}

  defp tftp_send_blocks(sock, host, port, data, block_num) do
    {chunk, rest} = split_512(data)
    packet = <<0, 3, block_num::16, chunk::binary>>
    :gen_udp.send(sock, host, port, packet)

    # Wait for ACK
    case :gen_udp.recv(sock, 0, 3_000) do
      {:ok, {_addr, _port, <<0, 4, ^block_num::16>>}} ->
        tftp_send_blocks(sock, host, port, rest, rem(block_num + 1, 65536))

      {:ok, {_, _, <<0, 5, code::16, msg::binary>>}} ->
        {:error, {:tftp_error, code, msg}}

      {:error, reason} ->
        {:error, {:tftp_timeout, reason}}
    end
  end

  defp split_512(data) when byte_size(data) <= 512, do: {data, <<>>}
  defp split_512(<<chunk::binary-size(512), rest::binary>>), do: {chunk, rest}

  # --- Config injection into .avm ---

  # AtomVM packbeam format: a sequence of beam files concatenated with
  # 4-byte size headers. We append a synthetic "priv/mulsp.config" module
  # that is actually a raw binary — mulsp reads it on boot via
  # :atomvm.read_priv/2 or equivalent.
  #
  # Format: <<size::32, "mulsp_config\n", config_etf::binary>>
  defp inject_config(base_avm, config_binary) do
    # Simple: append config as a named chunk at end of .avm
    # mulsp reads this via a startup hook that scans appended chunks
    marker = "LANG_CONFIG\n"
    chunk = marker <> config_binary
    patched = base_avm <> <<byte_size(chunk)::32, chunk::binary>>
    {:ok, patched}
  end

  defp read_avm(path) do
    case File.read(path) do
      {:ok, _} = ok -> ok
      {:error, :enoent} -> {:error, {:avm_not_found, path}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_node_id(role) do
    suffix =
      :crypto.strong_rand_bytes(6)
      |> Base.encode16(case: :lower)

    "mulsp-#{role}-#{suffix}"
  rescue
    _ -> "mulsp-#{role}-#{System.system_time(:millisecond)}"
  end
end
