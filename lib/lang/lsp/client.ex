defmodule Lang.LSP.Client do
  @moduledoc """
  LSP Client for making JSON-RPC requests.

  - Connects to `localhost:4001` by default
  - Frames requests using `Content-Length` headers per LSP/JSON-RPC
  - Supports both pooled and direct connections
  - Automatic retries and connection management
  - Handles LSP initialization protocol

  ## Options

  - `:host` (charlist) default `'127.0.0.1'`
  - `:port` (integer) default `4001`
  - `:timeout` (ms) default `5_000`
  - `:client_id` (string) unique client identifier
  - `:root_path` (string) workspace root path
  """

  require Logger

  @default_host ~c"127.0.0.1"
  @default_port 4001
  @default_timeout 5_000

  @type method() :: String.t()
  @type params() :: map() | nil
  @type rpc_response() :: {:ok, any()} | {:error, any()}
  @type connection() :: %{
          socket: :gen_tcp.socket(),
          client_id: String.t(),
          initialized: boolean()
        }

  @doc """
  Creates a persistent LSP connection with proper initialization.
  Returns a connection handle that can be used for multiple requests.
  """
  @spec connect(keyword()) :: {:ok, connection()} | {:error, any()}
  def connect(opts \\ []) do
    host = Keyword.get(opts, :host, @default_host)
    port = Keyword.get(opts, :port, @default_port)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    client_id = Keyword.get(opts, :client_id, generate_client_id())
    root_path = Keyword.get(opts, :root_path, System.cwd!())

    with {:ok, socket} <-
           :gen_tcp.connect(
             host,
             port,
             [:binary, packet: :raw, active: false, nodelay: true],
             timeout
           ),
         {:ok, _result} <- initialize_lsp(socket, client_id, root_path, timeout),
         :ok <- send_initialized_notification(socket) do
      {:ok, %{socket: socket, client_id: client_id, initialized: true}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Makes an LSP request using an existing connection.
  """
  @spec request_with_connection(connection(), method(), params(), keyword()) :: rpc_response()
  def request_with_connection(
        %{socket: socket, initialized: true},
        method,
        params \\ %{},
        opts \\ []
      ) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    :telemetry.span([:lang, :lsp, :client, :request], %{method: method}, fn ->
      result =
        with {:ok, id} <- generate_id(),
             :ok <- send_jsonrpc(socket, id, method, params),
             {:ok, resp} <- recv_jsonrpc(socket, timeout) do
          {:ok, resp}
        else
          {:error, reason} -> {:error, reason}
        end

      {result, %{method: method}}
    end)
  end

  @doc """
  Closes an LSP connection.
  """
  @spec disconnect(connection()) :: :ok
  def disconnect(%{socket: socket}) do
    :gen_tcp.close(socket)
  end

  @doc """
  Makes an LSP request via JSON-RPC (legacy method - uses short-lived connections).

  - `:host` (charlist) default `'127.0.0.1'`
  - `:port` (integer) default `4001`
  - `:timeout` (ms) default `5_000`
  """
  @spec request(method(), params(), keyword()) :: rpc_response()
  def request(method, params \\ %{}, opts \\ []) when is_binary(method) do
    # If pool is running and enabled, use it; otherwise short-lived TCP
    pool_pid = Process.whereis(Lang.LSP.ClientPool)

    case use_pool?() and pool_pid do
      true when is_pid(pool_pid) ->
        Lang.LSP.ClientPool.call(method, params, opts)

      _ ->
        # For short-lived connections, establish full LSP connection
        case connect(opts) do
          {:ok, conn} ->
            result = request_with_connection(conn, method, params, opts)
            disconnect(conn)
            result

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Initialize RPC and return server capabilities.
  """
  @spec initialize(keyword()) :: rpc_response()
  def initialize(opts \\ []) do
    request("rpc.initialize", %{}, opts)
  end

  @doc """
  Ping the server and return timestamp/latency.
  """
  @spec ping(keyword()) :: rpc_response()
  def ping(opts \\ []) do
    request("rpc.ping", %{timestamp: DateTime.utc_now() |> DateTime.to_iso8601()}, opts)
  end

  # ---------------------------------------------------------------------------
  # Internal: JSON-RPC framing (Content-Length)
  # ---------------------------------------------------------------------------

  # Initialize the LSP connection
  defp initialize_lsp(socket, client_id, root_path, timeout) do
    {:ok, id} = generate_id()

    init_params = %{
      "processId" => :os.getpid(),
      "clientInfo" => %{
        "name" => "Lang LSP Client",
        "version" => "1.0.0"
      },
      "rootPath" => root_path,
      "rootUri" => "file://#{root_path}",
      "capabilities" => %{
        "workspace" => %{
          "workspaceFolders" => true,
          "didChangeConfiguration" => %{"dynamicRegistration" => true}
        },
        "textDocument" => %{
          "completion" => %{
            "dynamicRegistration" => true,
            "completionItem" => %{
              "snippetSupport" => true
            }
          },
          "hover" => %{"dynamicRegistration" => true},
          "definition" => %{"dynamicRegistration" => true},
          "references" => %{"dynamicRegistration" => true}
        }
      }
    }

    with :ok <- send_jsonrpc(socket, id, "initialize", init_params),
         {:ok, result} <- recv_jsonrpc(socket, timeout) do
      Logger.info("LSP client #{client_id} initialized successfully")
      {:ok, result}
    end
  end

  # Send initialized notification (no response expected)
  defp send_initialized_notification(socket) do
    notification = %{
      "jsonrpc" => "2.0",
      "method" => "initialized",
      "params" => %{}
    }

    with {:ok, json_io} <- Jason.encode_to_iodata(notification) do
      len = :erlang.iolist_size(json_io)
      header_io = ["Content-Length: ", Integer.to_string(len), "\r\n\r\n"]
      :gen_tcp.send(socket, [header_io, json_io])
    end
  end

  defp send_jsonrpc(socket, id, method, params) do
    payload = %{"jsonrpc" => "2.0", "id" => id, "method" => method}

    payload =
      case params do
        nil -> payload
        %{} when map_size(params) == 0 -> payload
        _ -> Map.put(payload, "params", params)
      end

    with {:ok, json_io} <- Jason.encode_to_iodata(payload) do
      len = :erlang.iolist_size(json_io)
      header_io = ["Content-Length: ", Integer.to_string(len), "\r\n\r\n"]
      :gen_tcp.send(socket, [header_io, json_io])
    end
  end

  defp recv_jsonrpc(socket, timeout) do
    case recv_until_header(socket, "", timeout) do
      {:ok, content_length, rest} ->
        recv_body(socket, content_length, rest, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recv_until_header(socket, acc, timeout) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} ->
        buf = acc <> data

        case :binary.match(buf, "\r\n\r\n") do
          {hdr_end, 4} ->
            headers = :binary.part(buf, 0, hdr_end)
            rest = :binary.part(buf, hdr_end + 4, byte_size(buf) - (hdr_end + 4))

            case parse_content_length(headers) do
              {:ok, len} -> {:ok, len, rest}
              {:error, _} -> recv_until_header(socket, buf, timeout)
            end

          :nomatch ->
            recv_until_header(socket, buf, timeout)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_content_length(headers) when is_binary(headers) do
    case :binary.match(headers, "Content-Length: ") do
      {pos, _len} ->
        start = pos + byte_size("Content-Length: ")
        suffix = :binary.part(headers, start, byte_size(headers) - start)

        case :binary.match(suffix, "\r\n") do
          {eol, _} ->
            len_bin = :binary.part(suffix, 0, eol)

            case Integer.parse(len_bin) do
              {int, _} -> {:ok, int}
              :error -> {:error, :invalid_length}
            end

          :nomatch ->
            {:error, :no_eol}
        end

      :nomatch ->
        {:error, :no_content_length}
    end
  end

  defp recv_body(_socket, 0, rest, _timeout) do
    decode_json(rest)
  end

  defp recv_body(socket, len, rest, timeout) do
    have = byte_size(rest)

    cond do
      have == len ->
        decode_json(rest)

      have > len ->
        decode_json(binary_part(rest, 0, len))

      true ->
        remaining = len - have

        case :gen_tcp.recv(socket, remaining, timeout) do
          {:ok, data} -> decode_json(rest <> data)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp decode_json(binary) when is_binary(binary) do
    case Jason.decode(binary) do
      {:ok, %{"error" => err} = full} -> {:error, err}
      {:ok, %{"result" => result} = _full} -> {:ok, result}
      {:ok, other} -> {:ok, other}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp generate_id do
    {:ok, System.unique_integer([:positive])}
  end

  defp generate_client_id do
    "lang_client_#{System.unique_integer([:positive])}_#{:os.getpid()}"
  end

  defp use_pool? do
    case Application.get_env(:lang, :lsp_client) do
      cfg when is_list(cfg) -> Keyword.get(cfg, :use_pool, true)
      cfg when is_map(cfg) -> Map.get(cfg, :use_pool, true)
      _ -> true
    end
  end
end
