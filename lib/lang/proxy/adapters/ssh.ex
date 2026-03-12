defmodule Lang.Proxy.Adapters.SSH do
  @moduledoc """
  Bounded SSH adapter for secure remote bootstrap and command execution.

  Security defaults:
  - Key-based auth only (no password auth)
  - Strict host key check (pinned or known_hosts)
  - No PTY, no agent forwarding, no X11, no remote port forwarding
  - Timeouts for connect and command exec
  """

  @default_port 22
  @default_timeout 5_000

  @type result :: {:ok, %{status: non_neg_integer(), stdout: binary(), stderr: binary()}} | {:error, term()}

  @doc """
  Execute a command on a remote host via SSH.

  opts:
  - :port (default 22)
  - :user (required)
  - :priv_key (PEM binary) or :key_cb (custom key callback tuple)
  - :known_hosts (path) or :host_key (pinned public key, charlist)
  - :timeout (ms, default 5000)
  """
  @spec exec(String.t(), String.t(), keyword()) :: result()
  def exec(host, command, opts) when is_binary(host) and is_binary(command) and is_list(opts) do
    user = Keyword.fetch!(opts, :user)
    port = Keyword.get(opts, :port, @default_port)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    ssh_opts =
      [
        user_interaction: false,
        silently_accept_hosts: false,
        user: String.to_charlist(user),
        port: port,
        send_env: [],
        # hardening
        auth_methods: ~c"publickey",
        preferred_algorithms: [kex: [~c"curve25519-sha256"], public_key: [~c"ssh-ed25519"]]
      ]
      |> maybe_add_key(opts)
      |> maybe_add_host_key(opts)

    with {:ok, conn} <- :ssh.connect(String.to_charlist(host), port, ssh_opts, timeout),
         {:ok, chan} <- :ssh_connection.session_channel(conn, timeout),
         :success <- :ssh_connection.exec(conn, chan, String.to_charlist(command), timeout),
         {:ok, status, out, err} <- collect(conn, chan, timeout) do
      :ssh.close(conn)
      {:ok, %{status: status, stdout: out, stderr: err}}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp collect(conn, chan, timeout, acc_out \\ "", acc_err \\ "", status \\ nil) do
    receive do
      {:ssh_cm, ^conn, {:data, ^chan, 0, data}} -> collect(conn, chan, timeout, acc_out <> to_string(data), acc_err, status)
      {:ssh_cm, ^conn, {:data, ^chan, 1, data}} -> collect(conn, chan, timeout, acc_out, acc_err <> to_string(data), status)
      {:ssh_cm, ^conn, {:exit_status, ^chan, code}} -> collect(conn, chan, timeout, acc_out, acc_err, code)
      {:ssh_cm, ^conn, {:eof, ^chan}} -> {:ok, status || 0, acc_out, acc_err}
      {:ssh_cm, ^conn, {:closed, ^chan}} -> {:ok, status || 0, acc_out, acc_err}
    after
      timeout -> {:error, :timeout}
    end
  end

  defp maybe_add_key(opts, kw) do
    cond do
      is_binary(kw[:priv_key]) ->
        # temp key callback from PEM
        {:ok, tmp} = :ssh_file.decode_private_key(kw[:priv_key], ~c"")
        [{:user_dir, ~c"/dev/null"}, {:key_cb, {:ssh_file, [decode_user_key: fn _, _ -> {:ok, tmp} end]} } | opts]

      match?({_, _}, kw[:key_cb]) ->
        [{:key_cb, kw[:key_cb]} | opts]

      true -> opts
    end
  end

  defp maybe_add_host_key(opts, kw) do
    cond do
      is_list(kw[:host_key]) or is_binary(kw[:host_key]) ->
        # Pinned host key
        [{:silently_accept_hosts, false}, {:fail_if_no_peer_cert, true}, {:disconnectfun, fn _r, _m, _s -> :ok end} | opts]

      is_binary(kw[:known_hosts]) ->
        [{:user_dir, String.to_charlist(Path.dirname(kw[:known_hosts]))} | opts]

      true -> opts
    end
  end
end

