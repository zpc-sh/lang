defmodule Lang.Proxy.Adapters.Telnet do
  @moduledoc """
  Safe, bounded Telnet adapter for onboarding brittle agents.

  Security defaults:
  - Host allowlist (defaults to ["127.0.0.1", "::1", "localhost"]).
  - Passive sockets, line packet mode, bounded timeouts.
  - Max transcript size and step count caps.
  - Only sends exact lines provided (no shell escaping or interpolation).
  """

  @default_allow ["127.0.0.1", "::1", "localhost"]
  @default_timeout 3_000
  @max_steps 50
  @max_bytes 64 * 1024

  @type script_step :: {:expect, String.t() | Regex.t(), timeout() | nil} | {:send, String.t()}

  @spec run_script(String.t(), pos_integer(), [script_step()], keyword()) ::
          {:ok, %{steps: non_neg_integer(), transcript: binary()}} | {:error, term()}
  def run_script(host, port, script, opts \\ [])
      when is_binary(host) and is_integer(port) and is_list(script) do
    with :ok <- ensure_allowed_host(host),
         {:ok, socket} <- open(host, port, opts) do
      try do
        {count, transcript} = exec_script(socket, script, opts)
        :ok = :gen_tcp.close(socket)
        {:ok, %{steps: count, transcript: transcript}}
      after
        safe_close(socket)
      end
    end
  end

  defp open(host, port, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    :gen_tcp.connect(String.to_charlist(host), port, [:binary, {:packet, :line}, {:active, false}], timeout)
  end

  defp exec_script(socket, script, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_bytes = Keyword.get(opts, :max_bytes, @max_bytes)

    if length(script) > @max_steps do
      raise ArgumentError, "script too long"
    end

    Enum.reduce(script, {0, <<>>}, fn step, {i, acc} ->
      case step do
        {:send, line} when is_binary(line) ->
          :ok = send_line(socket, line)
          {i + 1, acc}

        {:expect, pattern} ->
          {:ok, got} = expect(socket, pattern, timeout, max_bytes)
          {i + 1, acc <> got}

        {:expect, pattern, step_timeout} ->
          {:ok, got} = expect(socket, pattern, step_timeout || timeout, max_bytes)
          {i + 1, acc <> got}

        other ->
          raise ArgumentError, "invalid script step: #{inspect(other)}"
      end
    end)
  end

  @spec expect(port(), String.t() | Regex.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, binary()} | {:error, term()}
  defp expect(socket, pattern, timeout, max_bytes) do
    do_expect(socket, pattern, timeout, max_bytes, <<>>)
  end

  defp do_expect(_socket, _pattern, _timeout, max_bytes, acc) when byte_size(acc) >= max_bytes,
    do: {:error, :max_bytes_exceeded}

  defp do_expect(socket, pattern, timeout, max_bytes, acc) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} ->
        buf = acc <> data
        if match_pattern?(buf, pattern) do
          {:ok, buf}
        else
          do_expect(socket, pattern, timeout, max_bytes, buf)
        end

      {:error, :timeout} -> {:error, :timeout}
      {:error, reason} -> {:error, reason}
    end
  end

  defp match_pattern?(data, %Regex{} = re), do: Regex.match?(re, data)
  defp match_pattern?(data, str) when is_binary(str), do: :binary.match(data, str) != :nomatch

  defp send_line(socket, line) do
    # Sanitize: disallow embedded CR/LF; we add CRLF ourselves
    cleaned = line |> String.replace(["\r", "\n"], " ") |> String.slice(0, 1024)
    :gen_tcp.send(socket, cleaned <> "\r\n")
  end

  defp ensure_allowed_host(host) do
    allow = Application.get_env(:lang, :telnet_allowlist, @default_allow)
    if is_list(allow) and host in allow do
      :ok
    else
      {:error, :host_not_allowed}
    end
  end

  defp safe_close(nil), do: :ok
  defp safe_close(socket) do
    try do
      :gen_tcp.close(socket)
    catch
      _, _ -> :ok
    end
  end
end

