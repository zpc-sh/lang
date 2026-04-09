defmodule Lang.Proxy.ChainConformance do
  @moduledoc """
  Replay/conformance utilities for proxy chain execution capture.

  - Replays from captured `hop_start` route decisions.
  - Supports optional per-hop remapping for resilience tests.
  - Emits hop-by-hop conformance divergence reports.
  """

  alias Lang.Proxy.{Envelope, Pipeline, StreamCapture}

  @spec replay(binary(), map(), map()) ::
          {:ok, %{pipeline_id: binary(), route_mode: atom(), remapped: non_neg_integer(), result: any()}}
          | {:error, term()}
  def replay(source_pipeline_id, opts, assigns \\ %{}) when is_binary(source_pipeline_id) and is_map(opts) do
    with {:ok, route} <- extract_route(source_pipeline_id),
         {:ok, replay_route, remapped} <- maybe_remap_route(route, Map.get(opts, "route_remap", %{})) do
      pipeline_id = Map.get(opts, "pipeline_id") || gen_id()
      mode = mode(opts)

      env = %Envelope{
        v: 1,
        service: :proxy,
        method: "pipeline.run",
        params: %{"route" => replay_route, "pipeline_id" => pipeline_id},
        opts: %{},
        meta: assigns,
        stream?: false
      }

      case Pipeline.run(env, assigns) do
        {:ok, result} ->
          {:ok,
           %{pipeline_id: pipeline_id, route_mode: mode, remapped: remapped, result: result}}

        {:error, code, message, data} ->
          {:error, %{code: code, message: message, data: data}}
      end
    end
  end

  def replay(_source_pipeline_id, _opts, _assigns), do: {:error, :invalid_source_pipeline_id}

  @spec report(binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def report(baseline_pipeline_id, candidate_pipeline_id, opts \\ %{}) do
    latency_tolerance_ms = Map.get(opts, "latency_tolerance_ms", 0)

    with {:ok, baseline} <- build_hop_summary(baseline_pipeline_id),
         {:ok, candidate} <- build_hop_summary(candidate_pipeline_id) do
      max_hops = max(length(baseline), length(candidate))

      rows =
        if max_hops == 0 do
          []
        else
          0..(max_hops - 1)
          |> Enum.map(fn idx ->
            b = Enum.at(baseline, idx)
            c = Enum.at(candidate, idx)
            compare_hop(idx, b, c, latency_tolerance_ms)
          end)
        end

      divergences = Enum.filter(rows, &(&1.status == :diverged))

      {:ok,
       %{
         baseline_pipeline_id: baseline_pipeline_id,
         candidate_pipeline_id: candidate_pipeline_id,
         total_hops: max_hops,
         diverged_hops: length(divergences),
         conformant: divergences == [],
         hops: rows
       }}
    end
  end

  defp extract_route(pipeline_id) do
    with {:ok, events} <- StreamCapture.list(pipeline_id) do
      route =
        events
        |> Enum.reverse()
        |> Enum.filter(&(Map.get(&1, "event") == "hop_start"))
        |> Enum.map(&Map.get(&1, "payload", %{}))
        |> Enum.map(&Map.get(&1, "route_decision", %{}))
        |> Enum.map(&Map.take(&1, ["service", "method", "params", :service, :method, :params]))
        |> Enum.map(&normalize_route_hop/1)
        |> Enum.reject(&is_nil/1)

      if route == [], do: {:error, :empty_route}, else: {:ok, route}
    end
  end

  defp maybe_remap_route(route, remap) when map_size(remap) == 0, do: {:ok, route, 0}

  defp maybe_remap_route(route, remap) do
    {new_route, remapped} =
      Enum.map_reduce(route, 0, fn hop, acc ->
        method = hop["method"]

        case Map.get(remap, method) do
          nil -> {hop, acc}
          new_method when is_binary(new_method) -> {Map.put(hop, "method", new_method), acc + 1}
          replacement when is_map(replacement) -> {Map.merge(hop, stringify_keys(replacement)), acc + 1}
          _ -> {hop, acc}
        end
      end)

    {:ok, new_route, remapped}
  end

  defp build_hop_summary(pipeline_id) do
    with {:ok, events} <- StreamCapture.list(pipeline_id) do
      by_uid =
        events
        |> Enum.reverse()
        |> Enum.reduce(%{}, fn ev, acc ->
          hop = Map.get(ev, "hop") || %{}
          uid = Map.get(hop, "uid") || Map.get(hop, :uid)
          key = uid || "idx:" <> Integer.to_string(map_size(acc))
          state = Map.get(acc, key, %{})
          Map.put(acc, key, apply_event(state, ev))
        end)

      hops = by_uid |> Map.values() |> Enum.sort_by(&Map.get(&1, :index, 999_999))
      {:ok, hops}
    end
  end

  defp apply_event(state, %{"event" => "hop_start", "hop" => hop, "payload" => payload}) do
    decision = Map.get(payload, "route_decision", %{})

    state
    |> Map.put_new(:service, Map.get(decision, "service") || Map.get(hop, "service"))
    |> Map.put_new(:method, Map.get(decision, "method") || Map.get(hop, "method"))
    |> Map.put_new(:index, Map.get(payload, "index"))
    |> Map.put_new(:uid, Map.get(hop, "uid"))
  end

  defp apply_event(state, %{"event" => "hop_stop", "payload" => payload}) do
    state
    |> Map.put(:status, :ok)
    |> Map.put(:latency_ms, Map.get(payload, "latency_ms"))
  end

  defp apply_event(state, %{"event" => "hop_error", "payload" => payload}) do
    state
    |> Map.put(:status, :error)
    |> Map.put(:latency_ms, Map.get(payload, "latency_ms"))
    |> Map.put(:reason_code, Map.get(payload, "reason_code") || Map.get(payload, "code"))
  end

  defp apply_event(state, _), do: state

  defp compare_hop(idx, nil, candidate, _tol), do: %{index: idx, status: :diverged, reason_code: :missing_baseline_hop, baseline: nil, candidate: candidate}
  defp compare_hop(idx, baseline, nil, _tol), do: %{index: idx, status: :diverged, reason_code: :missing_candidate_hop, baseline: baseline, candidate: nil}

  defp compare_hop(idx, baseline, candidate, tol) do
    cond do
      baseline.method != candidate.method ->
        %{index: idx, status: :diverged, reason_code: :method_mismatch, baseline: baseline, candidate: candidate}

      baseline.service != candidate.service ->
        %{index: idx, status: :diverged, reason_code: :service_mismatch, baseline: baseline, candidate: candidate}

      Map.get(baseline, :status, :ok) != Map.get(candidate, :status, :ok) ->
        %{index: idx, status: :diverged, reason_code: :status_mismatch, baseline: baseline, candidate: candidate}

      Map.get(baseline, :reason_code) != Map.get(candidate, :reason_code) ->
        %{index: idx, status: :diverged, reason_code: :reason_code_mismatch, baseline: baseline, candidate: candidate}

      latency_diverged?(baseline, candidate, tol) ->
        %{index: idx, status: :diverged, reason_code: :latency_out_of_tolerance, baseline: baseline, candidate: candidate}

      true ->
        %{index: idx, status: :conformant, reason_code: :none, baseline: baseline, candidate: candidate}
    end
  end

  defp latency_diverged?(baseline, candidate, tol) when is_integer(tol) and tol >= 0 do
    b = Map.get(baseline, :latency_ms)
    c = Map.get(candidate, :latency_ms)

    case {b, c} do
      {bi, ci} when is_integer(bi) and is_integer(ci) -> abs(bi - ci) > tol
      _ -> false
    end
  end

  defp mode(opts), do: if(map_size(Map.get(opts, "route_remap", %{})) > 0, do: :remapped, else: :original)

  defp normalize_route_hop(hop) when is_map(hop) do
    service = Map.get(hop, "service") || Map.get(hop, :service)
    method = Map.get(hop, "method") || Map.get(hop, :method)

    if is_nil(service) or is_nil(method) do
      nil
    else
      %{
        "service" => service,
        "method" => method,
        "params" => Map.get(hop, "params") || Map.get(hop, :params) || %{}
      }
    end
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp gen_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end
end
