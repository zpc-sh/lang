defmodule Lang.Proxy.Envelope do
  @moduledoc """
  Versioned proxy request envelope used across brokered services.

  Fields:
  - v: protocol version (integer)
  - service: target logical service (e.g., :ai, :lsp, :mcp)
  - method: method/operation name within the service
  - params: request parameters (map)
  - opts: routing options (timeout_ms, provider, cost_priority, etc.)
  - meta: trace/user/org/session metadata
  - stream?: whether streaming is desired (when supported)
  """

  @type t :: %__MODULE__{
          v: pos_integer(),
          service: atom(),
          method: String.t(),
          params: map(),
          opts: keyword() | map(),
          meta: map(),
          stream?: boolean()
        }
  defstruct v: 1, service: :ai, method: "", params: %{}, opts: %{}, meta: %{}, stream?: false

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(map) when is_map(map) do
    try do
      v = Map.get(map, "v", Map.get(map, :v, 1))
      service = map |> Map.get("service") |> or_else(fn -> Map.get(map, :service) end)
      method = map |> Map.get("method") |> or_else(fn -> Map.get(map, :method) end) || ""
      params = map |> Map.get("params") |> or_else(fn -> Map.get(map, :params) end) || %{}
      opts = map |> Map.get("opts") |> or_else(fn -> Map.get(map, :opts) end) || %{}
      meta = map |> Map.get("meta") |> or_else(fn -> Map.get(map, :meta) end) || %{}
      stream? = map |> Map.get("stream") |> or_else(fn -> Map.get(map, :stream?) end) || false

      with true <- is_integer(v) and v >= 1 or {:error, :invalid_version},
           {:ok, svc} <- normalize_service(service),
           true <- is_binary(method) or {:error, :invalid_method},
           true <- is_map(params) or {:error, :invalid_params} do
        {:ok,
         %__MODULE__{
           v: v,
           service: svc,
           method: method,
           params: params,
           opts: opts,
           meta: meta,
           stream?: !!stream?
         }}
      else
        {:error, reason} -> {:error, reason}
        false -> {:error, :invalid_envelope}
        _ -> {:error, :invalid_envelope}
      end
    rescue
      e -> {:error, {:invalid_envelope, e}}
    end
  end

  defp normalize_service(s) when is_atom(s), do: {:ok, s}
  defp normalize_service(s) when is_binary(s) do
    case String.downcase(s) do
      "ai" -> {:ok, :ai}
      "lsp" -> {:ok, :lsp}
      "mcp" -> {:ok, :mcp}
      "proxy" -> {:ok, :proxy}
      other -> {:ok, String.to_atom(other)}
    end
  end

  defp normalize_service(nil), do: {:ok, :ai}

  defp or_else(nil, fun) when is_function(fun, 0), do: fun.()
  defp or_else(v, _), do: v
end

