defmodule Lang.Proxy.SSH do
  @moduledoc """
  Minimal SSH PTY proxy for WebSocket sessions.

  - Connects via `:ssh`.
  - Allocates PTY and starts interactive shell.
  - Forwards stdout/stderr to the WebSocket process.
  - Accepts stdin and resize commands.

  Note: Credentials are not handled here. This expects host to accept
  configured keys under the BEAM user, or host policy that permits connection
  without prompting. Fingerprint pinning is logged for now.
  """

  use GenServer
  require Logger

  @type state :: %{
          ws: pid(),
          host: String.t(),
          port: pos_integer(),
          user: String.t() | nil,
          finger: String.t() | nil,
          conn_ref: term() | nil,
          chan: term() | nil,
          cols: non_neg_integer(),
          rows: non_neg_integer()
        }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Start a new SSH PTY session.
  Options:
  - :ws (required) target WebSocket pid to stream outputs
  - :host (required), :port (default 22), :user (optional), :fingerprint (optional), :cols, :rows
  """
  def start(ws, host, port, user, fingerprint, cols, rows) do
    start_link(ws: ws, host: host, port: port, user: user, fingerprint: fingerprint, cols: cols, rows: rows)
  end

  @impl true
  def init(opts) do
    ws = Keyword.fetch!(opts, :ws)
    host = Keyword.fetch!(opts, :host)
    port = Keyword.get(opts, :port, 22)
    user = Keyword.get(opts, :user)
    finger = Keyword.get(opts, :fingerprint)
    cols = Keyword.get(opts, :cols, 80)
    rows = Keyword.get(opts, :rows, 24)

    # If fingerprint provided, ensure known_hosts contains a key whose SHA256 matches
    state = %{ws: ws, host: host, port: port, user: user, finger: finger, conn_ref: nil, chan: nil, cols: cols, rows: rows}
    case ensure_fingerprint_pinned(host, finger) do
      :ok ->
        send(self(), :connect)
        {:ok, state}

      {:error, reason} ->
        send(ws, {:proxy_stdout, "[ssh] fingerprint not pinned: #{inspect(reason)}\\r\\n"})
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_info(:connect, %{host: host, port: port, user: user} = state) do
    user_dir = Application.get_env(:lang, :ssh_user_dir)
    opts = [
      silently_accept_hosts: false,
      save_accepted_host: false,
      user_interaction: false,
      connect_timeout: 3_000,
      auth_methods: ~c"publickey",
      preferred_algorithms: [kex: [~c"curve25519-sha256"], public_key: [~c"ssh-ed25519"]]
    ]
    opts = if is_binary(user_dir), do: [{:user_dir, String.to_charlist(user_dir)} | opts], else: opts
    opts = if is_binary(user), do: [{:user, String.to_charlist(user)} | opts], else: opts

    case :ssh.connect(String.to_charlist(host), port, opts) do
      {:ok, conn_ref} ->
        send(state.ws, {:proxy_stdout, "[ssh] connected to #{host}:#{port}\r\n"})
        # Optional explicit host key verification (best-effort)
        case verify_remote_hostkey(conn_ref, state.finger) do
          :ok -> :ok
          {:error, reason} ->
            send(state.ws, {:proxy_stdout, "[ssh] host key verification failed: #{inspect(reason)}\r\n"})
            :ssh.close(conn_ref)
            {:stop, reason, state}
        end
        # Fingerprint pinning via known_hosts provisioning:
        # With silently_accept_hosts: false and save_accepted_host: false,
        # :ssh will only connect when the host key matches entries in known_hosts.
        # If a fingerprint was provided but no user_dir is configured, warn admin.
        if state.finger && is_nil(user_dir) do
          Logger.warning("SSH fingerprint provided but :ssh_user_dir not configured; ensure known_hosts contains the pinned key for #{host}")
        end

        case :ssh_connection.session(conn_ref) do
          {:ok, chan} ->
            term = 'xterm-256color'
            _ = :ssh_connection.pty_alloc(conn_ref, chan, term, state.cols, state.rows, 0, 0, [])
            _ = :ssh_connection.shell(conn_ref, chan)
            {:noreply, %{state | conn_ref: conn_ref, chan: chan}}

          {:error, reason} ->
            send(state.ws, {:proxy_stdout, "[ssh] failed to create session: #{inspect(reason)}\r\n"})
            {:stop, reason, state}
        end

      {:error, reason} ->
        send(state.ws, {:proxy_stdout, "[ssh] connect error: #{inspect(reason)}\r\n"})
        {:stop, reason, state}
    end
  end

  def handle_info({:ssh_cm, conn_ref, {:data, chan, _type, data}}, %{ws: ws, conn_ref: conn_ref, chan: chan} = state) do
    send(ws, {:proxy_stdout, data})
    {:noreply, state}
  end

  def handle_info({:ssh_cm, conn_ref, {:eof, chan}}, %{ws: ws, conn_ref: conn_ref, chan: chan} = state) do
    send(ws, {:proxy_exit, 0})
    {:stop, :normal, state}
  end

  def handle_info({:ssh_cm, conn_ref, {:exit_status, chan, status}}, %{ws: ws, conn_ref: conn_ref, chan: chan} = state) do
    send(ws, {:proxy_exit, status})
    {:noreply, state}
  end

  def handle_info({:ssh_cm, _conn_ref, _other}, state), do: {:noreply, state}

  @impl true
  def handle_cast({:stdin, data}, %{conn_ref: conn, chan: chan} = state) when is_binary(data) do
    if conn && chan, do: :ssh_connection.send(conn, chan, data)
    {:noreply, state}
  end

  def handle_cast({:resize, cols, rows}, %{conn_ref: conn, chan: chan} = state) do
    if conn && chan, do: :ssh_connection.window_change(conn, chan, cols, rows, 0, 0)
    {:noreply, %{state | cols: cols, rows: rows}}
  end

  @impl true
  def terminate(_reason, %{conn_ref: conn} = _state) when not is_nil(conn) do
    try do
      :ssh.close(conn)
    catch
      _, _ -> :ok
    end
    :ok
  end

  def terminate(_reason, _state), do: :ok

  #
  # Pinned fingerprint validation via known_hosts scanning
  #
  defp ensure_fingerprint_pinned(_host, nil), do: :ok
  defp ensure_fingerprint_pinned(host, finger) when is_binary(host) and is_binary(finger) do
    case Application.get_env(:lang, :ssh_user_dir) do
      dir when is_binary(dir) ->
        known_hosts = Path.join(dir, "known_hosts")
        case Lang.Native.FSScanner.preview(known_hosts, max_lines: 10_000) do
          {:ok, lines} ->
            norm_f = normalize_fingerprint(finger)
            match? =
              lines
              |> Enum.reject(&String.starts_with?(&1, "#"))
              |> Enum.any?(fn line -> match_known_host_line?(line, host, norm_f) end)
            if match?, do: :ok, else: {:error, :pinned_fingerprint_not_found}
          {:error, reason} -> {:error, {:cannot_read_known_hosts, reason}}
        end

      _ -> {:error, :ssh_user_dir_not_configured}
    end
  end

  defp match_known_host_line?(line, host, norm_f) do
    parts = String.split(line |> String.trim(), ~r/\s+/, parts: 3)
    case parts do
      [hosts_field, _alg, key_b64] ->
        host_matches =
          hosts_field
          |> String.split(",")
          |> Enum.any?(fn h -> not String.starts_with?(h, "|") and String.downcase(String.trim(h)) == String.downcase(host) end)

        if host_matches do
          case Base.decode64(key_b64) do
            {:ok, key} ->
              calc = normalize_fingerprint("sha256:" <> Base.encode64(:crypto.hash(:sha256, key), padding: false))
              calc == norm_f
            _ -> false
          end
        else
          false
        end

      _ -> false
    end
  end

  defp normalize_fingerprint(f) when is_binary(f) do
    f
    |> String.trim()
    |> String.replace_prefix("SHA256:", "sha256:")
    |> then(fn s -> if String.starts_with?(s, "sha256:"), do: s, else: "sha256:" <> s end) 
    |> String.downcase()
  end

  # Best-effort explicit verification; depends on OTP internals. Falls back to :ok when not supported.
  defp verify_remote_hostkey(_conn_ref, nil), do: :ok
  defp verify_remote_hostkey(conn_ref, finger) do
    norm_f = normalize_fingerprint(finger)
    try do
      # Attempt to query server host key via :ssh connection_info
      info = :ssh.connection_info(conn_ref, [:server_version, :server_host_key])
      case info do
        {:ok, kv} ->
          case Keyword.get(kv, :server_host_key) do
            key when is_binary(key) ->
              calc = normalize_fingerprint("sha256:" <> Base.encode64(:crypto.hash(:sha256, key), padding: false))
              if calc == norm_f, do: :ok, else: {:error, :fingerprint_mismatch}
            _ -> :ok
          end
        _ -> :ok
      end
    catch
      _, _ -> :ok
    rescue
      _ -> :ok
    end
  end
end
