defmodule Lang.Dev.LSPTracer do
  @moduledoc """
  Utilities to manage LSP taps and record traces (dev-only).

  - Tap configs are stored in Lang.Dev.LSPTap (ETS).
  - Traces are stored in Lang.Dev.LSPTrace (ETS), with digest and preview only.
  """

  import Ash.Query

  @preview_max 512

  def configure(client_id, attrs) do
    now = DateTime.utc_now()
    attrs = Map.merge(%{"client_id" => client_id, "updated_at" => now}, attrs)
    case Lang.Dev.LSPTap.upsert(attrs) do
      {:ok, rec} -> {:ok, normalize_tap(rec)}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_tap(client_id) do
    case Lang.Dev.LSPTap |> filter(client_id == ^client_id) |> Ash.read() do
      {:ok, [rec | _]} -> {:ok, normalize_tap(rec)}
      _ -> {:ok, %{client_id: client_id, active: false, methods: [], max: 500}}
    end
  end

  def tapped?(client_id, method) do
    case get_tap(client_id) do
      {:ok, %{active: true, methods: methods}} -> methods == [] or method in methods
      _ -> false
    end
  end

  def record(client_id, dir, method, rpc_id, status, duration_ms, payload), do:
    record(client_id, dir, method, rpc_id, status, duration_ms, payload, nil)

  def record(client_id, dir, method, rpc_id, status, duration_ms, payload, error) do
    preview = build_preview(payload)
    digest = payload_digest(payload)
    args = %{
      client_id: client_id,
      dir: dir,
      method: method,
      rpc_id: to_string(rpc_id || ""),
      status: status && to_string(status),
      duration_ms: duration_ms && trunc(duration_ms),
      payload_digest: digest,
      payload_preview: preview,
      error: error && to_string(error)
    }
    Lang.Dev.LSPTrace.log(args)
  end

  def list_traces(client_id, opts \\ %{}) do
    method = Map.get(opts, "method") || Map.get(opts, :method)
    since = Map.get(opts, "since") || Map.get(opts, :since)
    limit = Map.get(opts, "limit") || Map.get(opts, :limit) || 200

    base = Lang.Dev.LSPTrace |> filter(client_id == ^client_id)
    base = if method, do: base |> filter(method == ^method), else: base
    base =
      if since do
        case parse_iso(since) do
          {:ok, dt} -> base |> filter(at >= ^dt)
          _ -> base
        end
      else
        base
      end

    case base |> Ash.read() do
      {:ok, rows} ->
        rows
        |> Enum.sort_by(& &1.at, DateTime)
        |> Enum.take(-limit)
        |> Enum.map(&trace_map/1)
        |> then(&{:ok, &1})
      other -> other
    end
  end

  defp parse_iso(val) when is_binary(val) do
    case DateTime.from_iso8601(val) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> {:error, :invalid}
    end
  end
  defp parse_iso(_), do: {:error, :invalid}

  defp trace_map(r) do
    %{
      id: r.id,
      client_id: r.client_id,
      dir: r.dir,
      method: r.method,
      rpc_id: r.rpc_id,
      status: r.status,
      duration_ms: r.duration_ms,
      payload_digest: r.payload_digest,
      payload_preview: r.payload_preview,
      error: r.error,
      at: r.at
    }
  end

  defp normalize_tap(rec) do
    %{
      client_id: rec.client_id,
      active: rec.active,
      methods: parse_methods(rec.methods),
      max: rec.max,
      updated_at: rec.updated_at
    }
  end

  defp parse_methods(nil), do: []
  defp parse_methods("") , do: []
  defp parse_methods(str) when is_binary(str), do: String.split(str, ",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  defp parse_methods(list) when is_list(list), do: list

  defp build_preview(nil), do: nil
  defp build_preview(bin) when is_binary(bin) do
    bin
    |> String.slice(0, @preview_max)
  end
  defp build_preview(map) when is_map(map) do
    map |> Jason.encode!() |> build_preview()
  end
  defp build_preview(other), do: other |> inspect(limit: :infinity) |> build_preview()

  defp payload_digest(nil), do: nil
  defp payload_digest(bin) when is_binary(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)
  defp payload_digest(map) when is_map(map), do: payload_digest(Jason.encode!(map))
  defp payload_digest(other), do: payload_digest(inspect(other, limit: :infinity))
end
