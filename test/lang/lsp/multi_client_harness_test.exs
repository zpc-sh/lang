defmodule Lang.LSP.MultiClientHarnessTest do
  use ExUnit.Case, async: false

  alias Lang.LSP.Client

  @moduletag :integration

  test "simulates multiple concurrent clients with edits and requests" do
    {:ok, _} = Application.ensure_all_started(:lang)

    host = (System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
    port = String.to_integer(System.get_env("LSP_PORT") || "4001")

    n = 4

    results =
      1..n
      |> Task.async_stream(fn i -> one_client_roundtrip(i, host, port) end, max_concurrency: n, timeout: 15_000)
      |> Enum.map(fn {:ok, res} -> res end)

    assert Enum.all?(results, &match?(:ok, &1))
  end

  test "conflict scenario with shared URI handles concurrent writes" do
    {:ok, _} = Application.ensure_all_started(:lang)

    host = (System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
    port = String.to_integer(System.get_env("LSP_PORT") || "4001")

    n = 3
    shared_uri = "file:///tmp/harness_shared_test.ex"
    System.put_env("HARNESS_SHARED_URI", shared_uri)

    results =
      1..n
      |> Task.async_stream(fn i -> one_client_conflict(i, host, port, shared_uri) end, max_concurrency: n, timeout: 15_000)
      |> Enum.map(fn {:ok, res} -> res end)

    assert Enum.all?(results, &match?(:ok, &1))
  after
    System.delete_env("HARNESS_SHARED_URI")
  end

  test "formatting and rename scenario on a single client" do
    {:ok, _} = Application.ensure_all_started(:lang)

    host = (System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
    port = String.to_integer(System.get_env("LSP_PORT") || "4001")

    client_id = "format_rename_client_#{System.unique_integer([:positive])}"
    root = System.cwd!()

    {:ok, conn} = Client.connect(host: host, port: port, client_id: client_id, root_path: root, timeout: 5_000)
    :ok = notify_conn(conn, "lang/tester/identify", %{"clientId" => client_id})

    uri = "file:///tmp/#{client_id}.ex"
    text = "defmodule FR do\n  def hello(name), do: name\nend\n"
    :ok = notify_conn(conn, "textDocument/didOpen", %{"textDocument" => %{"uri" => uri, "languageId" => "elixir", "version" => 1, "text" => text}})

    fmt = Client.request_with_connection(conn, "textDocument/formatting", %{"textDocument" => %{"uri" => uri}, "options" => %{"tabSize" => 2, "insertSpaces" => true}}, timeout: 4_000)
    assert match?({:ok, _}, fmt)

    rn = Client.request_with_connection(conn, "textDocument/rename", %{"textDocument" => %{"uri" => uri}, "position" => %{"line" => 1, "character" => 8}, "newName" => "hello2"}, timeout: 4_000)
    assert match?({:ok, _}, rn)

    Client.disconnect(conn)
  end

  defp one_client_conflict(i, host, port, uri) do
    client_id = "conflict_agent_#{i}_#{System.unique_integer([:positive])}"
    root = System.cwd!()

    with {:ok, conn} <- Client.connect(host: host, port: port, client_id: client_id, root_path: root, timeout: 5_000),
         :ok <- notify_conn(conn, "lang/tester/identify", %{"clientId" => client_id}) do
      text = "defmodule Conflict#{i} do\n  def x, do: :ok\nend\n"
      :ok = notify_conn(conn, "textDocument/didOpen", %{"textDocument" => %{"uri" => uri, "languageId" => "elixir", "version" => 1, "text" => text}})
      :ok = notify_conn(conn, "textDocument/didChange", %{"textDocument" => %{"uri" => uri, "version" => 2}, "contentChanges" => [%{"text" => text <> "\n# client #{client_id}"}]})

      res = Client.request_with_connection(conn, "textDocument/hover", %{"textDocument" => %{"uri" => uri}, "position" => %{"line" => 0, "character" => 10}}, timeout: 3_000)
      Client.disconnect(conn)
      assert match?({:ok, _}, res)
      :ok
    else
      other -> other
    end
  end

  defp one_client_roundtrip(i, host, port) do
    client_id = "test_agent_#{i}_#{System.unique_integer([:positive])}"
    root = System.cwd!()

    with {:ok, conn} <- Client.connect(host: host, port: port, client_id: client_id, root_path: root, timeout: 5_000),
         :ok <- notify_conn(conn, "lang/tester/identify", %{"clientId" => client_id}) do
      uri = "file:///tmp/#{client_id}.ex"
      text = "defmodule Harness#{i} do\n  def hello(name), do: name\nend\n"

      open = %{
        "textDocument" => %{
          "uri" => uri,
          "languageId" => "elixir",
          "version" => 1,
          "text" => text
        }
      }

      :ok = notify_conn(conn, "textDocument/didOpen", open)

      comp = Client.request_with_connection(conn, "textDocument/completion", %{"textDocument" => %{"uri" => uri}, "position" => %{"line" => 1, "character" => 10}}, timeout: 3_000)
      hov = Client.request_with_connection(conn, "textDocument/hover", %{"textDocument" => %{"uri" => uri}, "position" => %{"line" => 0, "character" => 10}}, timeout: 3_000)

      Client.disconnect(conn)

      assert {:ok, resp1} = comp
      assert is_list(resp1) or is_map(resp1)
      assert match?({:ok, _}, hov)
      :ok
    else
      other -> other
    end
  end

  defp notify_conn(%{socket: socket}, method, params) do
    payload = %{"jsonrpc" => "2.0", "method" => method} |> maybe_put_params(params)
    {:ok, json} = Jason.encode_to_iodata(payload)
    len = :erlang.iolist_size(json)
    header = ["Content-Length: ", Integer.to_string(len), "\r\n\r\n"]
    case :gen_tcp.send(socket, [header, json]) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_params(map, nil), do: map
  defp maybe_put_params(map, %{} = params) when map_size(params) == 0, do: map
  defp maybe_put_params(map, params), do: Map.put(map, "params", params)
end
