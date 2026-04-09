defmodule Lang.Proxy.ChainConformanceTest do
  use ExUnit.Case, async: true
  import Mock

  alias Lang.Proxy.ChainConformance

  describe "replay/3" do
    test "replays against original captured chain" do
      captured = [
        %{
          "event" => "hop_start",
          "hop" => %{"uid" => "h1", "service" => :lsp, "method" => "lsp.bootstrap"},
          "payload" => %{"index" => 0, "route_decision" => %{"service" => :lsp, "method" => "lsp.bootstrap", "params" => %{"workspace" => "/tmp"}}}
        }
      ]

      with_mock Lang.Proxy.StreamCapture,
        list: fn "base-1" -> {:ok, captured} end do
        with_mock Lang.Proxy.Pipeline,
          run: fn _env, _assigns -> {:ok, [%{hop: %{service: :lsp, method: "lsp.bootstrap"}, result: %{status: :ok}, latency_ms: 5}]} end do
          assert {:ok, %{route_mode: :original, remapped: 0, result: [_]}} =
                   ChainConformance.replay("base-1", %{}, %{})
        end
      end
    end

    test "replays against remapped chain" do
      captured = [
        %{
          "event" => "hop_start",
          "hop" => %{"uid" => "h1", "service" => :lsp, "method" => "lsp.bootstrap"},
          "payload" => %{"index" => 0, "route_decision" => %{"service" => :lsp, "method" => "lsp.bootstrap", "params" => %{}}}
        }
      ]

      with_mock Lang.Proxy.StreamCapture,
        list: fn "base-2" -> {:ok, captured} end do
        with_mock Lang.Proxy.Pipeline,
          run: fn env, _assigns ->
            assert [%{"method" => "lsp.bootstrap_ssh"}] = env.params["route"]
            {:ok, [%{hop: %{service: :lsp, method: "lsp.bootstrap_ssh"}, result: %{status: :ok}, latency_ms: 4}]}
          end do
          assert {:ok, %{route_mode: :remapped, remapped: 1}} =
                   ChainConformance.replay("base-2", %{"route_remap" => %{"lsp.bootstrap" => "lsp.bootstrap_ssh"}}, %{})
        end
      end
    end
  end

  describe "report/3" do
    test "reports divergence with reason code by hop" do
      baseline = [
        %{"event" => "hop_start", "hop" => %{"uid" => "h1"}, "payload" => %{"index" => 0, "route_decision" => %{"service" => :lsp, "method" => "lsp.bootstrap"}}},
        %{"event" => "hop_stop", "hop" => %{"uid" => "h1"}, "payload" => %{"latency_ms" => 5}},
        %{"event" => "hop_start", "hop" => %{"uid" => "h2"}, "payload" => %{"index" => 1, "route_decision" => %{"service" => :lsp, "method" => "lsp.symbols"}}},
        %{"event" => "hop_stop", "hop" => %{"uid" => "h2"}, "payload" => %{"latency_ms" => 10}}
      ]

      candidate = [
        %{"event" => "hop_start", "hop" => %{"uid" => "h1"}, "payload" => %{"index" => 0, "route_decision" => %{"service" => :lsp, "method" => "lsp.bootstrap"}}},
        %{"event" => "hop_stop", "hop" => %{"uid" => "h1"}, "payload" => %{"latency_ms" => 7}},
        %{"event" => "hop_start", "hop" => %{"uid" => "h2"}, "payload" => %{"index" => 1, "route_decision" => %{"service" => :lsp, "method" => "lsp.symbols"}}},
        %{"event" => "hop_error", "hop" => %{"uid" => "h2"}, "payload" => %{"code" => -32050, "reason_code" => -32050, "latency_ms" => 30}}
      ]

      with_mocks([
        {Lang.Proxy.StreamCapture, [], [
          list: fn
            "baseline" -> {:ok, baseline}
            "candidate" -> {:ok, candidate}
          end
        ]}
      ]) do
        assert {:ok, report} = ChainConformance.report("baseline", "candidate", %{"latency_tolerance_ms" => 3})
        assert report.total_hops == 2
        assert report.diverged_hops == 1
        assert Enum.any?(report.hops, &(&1.reason_code == :status_mismatch))
      end
    end
  end
end
