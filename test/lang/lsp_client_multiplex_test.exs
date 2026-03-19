defmodule Lang.LSPClientMultiplexTest do
  use ExUnit.Case, async: false

  setup_all do
    # Disable NIFs and DB
    System.put_env("SKIP_NIFS", "1")
    System.put_env("SKIP_DB", "1")
    System.put_env("LSP_TELEMETRY_LOG", "0")
    :ok
  end

  setup do
    {:ok, _srv} = FakeLSPServer.start_link()
    {:ok, port} = GenServer.call(FakeLSPServer, {:start, 0})
    {:ok, port: port}
  end

  test "handles concurrent inflight requests over single worker", %{port: port} do
    {:ok, pid} =
      Lang.LSP.ClientWorker.start_link(
        host: ~c"127.0.0.1",
        port: port,
        root_path: System.cwd!(),
        max_inflight: 16
      )

    reqs =
      for i <- 1..10 do
        delay = 10 * rem(i, 3)

        Task.async(fn ->
          # GenServer.call through worker call API
          Lang.LSP.ClientWorker.call(pid, "test.echo", %{"seq" => i, "delay_ms" => delay},
            timeout: 1_000
          )
        end)
      end

    results = Enum.map(reqs, &Task.await(&1, 2_000))

    assert Enum.all?(results, fn {:ok, %{"seq" => n, "delay_ms" => _}} -> is_integer(n) end)
    assert Enum.sort(Enum.map(results, fn {:ok, %{"seq" => n}} -> n end)) == Enum.to_list(1..10)
  end

  test "returns backpressure when inflight exceeds max", %{port: port} do
    {:ok, pid} =
      Lang.LSP.ClientWorker.start_link(
        host: ~c"127.0.0.1",
        port: port,
        root_path: System.cwd!(),
        max_inflight: 2
      )

    # Start two long-running calls to occupy inflight slots
    t1 =
      Task.async(fn ->
        Lang.LSP.ClientWorker.call(pid, "test.echo", %{"seq" => 1, "delay_ms" => 300},
          timeout: 1_000
        )
      end)

    t2 =
      Task.async(fn ->
        Lang.LSP.ClientWorker.call(pid, "test.echo", %{"seq" => 2, "delay_ms" => 300},
          timeout: 1_000
        )
      end)

    # Third call should hit backpressure immediately
    resp =
      Lang.LSP.ClientWorker.call(pid, "test.echo", %{"seq" => 3, "delay_ms" => 0}, timeout: 1_000)

    assert {:error, :backpressure} = resp

    # Let the first two finish
    assert {:ok, %{"seq" => 1}} = Task.await(t1, 2_000)
    assert {:ok, %{"seq" => 2}} = Task.await(t2, 2_000)
  end
end
