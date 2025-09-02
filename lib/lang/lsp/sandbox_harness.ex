defmodule Lang.LSP.SandboxHarness do
  @moduledoc """
  In-process, socket-free harness for exercising LSP methods via `Lang.LSP.Dispatch`.

  - Avoids TCP/stdio servers and Mix tasks to run in constrained sandboxes
  - Uses NIF FSScanner for reading inputs when needed
  - Skips methods that require PubSub streaming unless explicitly allowed
  """

  alias Lang.LSP.Dispatch

  @type call :: %{required("method") => String.t(), optional("params") => map()}
  @type result :: %{method: String.t(), duration_ms: non_neg_integer(), response: map() | nil}

  @doc "Run a single LSP call (map must have \"method\" and optional \"params\")."
  @spec run_call(call()) :: result()
  def run_call(%{"method" => method} = call) do
    id = System.unique_integer([:positive])
    msg = %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => Map.get(call, "params", %{})}
    t0 = System.monotonic_time(:millisecond)
    resp = safe_dispatch(msg)
    dt = System.monotonic_time(:millisecond) - t0
    %{method: method, duration_ms: dt, response: resp}
  end

  @doc "Run a list of LSP calls and return list of results with timings."
  @spec run_calls([call()]) :: [result()]
  def run_calls(calls) when is_list(calls) do
    Enum.map(calls, &run_call/1)
  end

  @doc "Convenience: run review fast-path with inline code."
  @spec review_code_fast(String.t()) :: result()
  def review_code_fast(code) when is_binary(code) do
    run_call(%{"method" => "lang.think.review_code", "params" => %{"code" => code, "realtime" => true}})
  end

  defp safe_dispatch(message) do
    try do
      Dispatch.process(message)
    rescue
      e -> %{"jsonrpc" => "2.0", "id" => message["id"], "error" => %{code: -32099, message: Exception.message(e)}}
    catch
      _, _ -> %{"jsonrpc" => "2.0", "id" => message["id"], "error" => %{code: -32098, message: "dispatch_crash"}}
    end
  end
end

