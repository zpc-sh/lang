defmodule Lang.Proxy.CaptureSchema do
  @moduledoc """
  Canonical schema helpers for proxy capture/replay records.

  Each record contains:
  - canonical_request (normalized envelope map)
  - canonical_response (normalized router result map)
  - route_path
  - dependency_refs
  - trace_id / idempotency_key indexes
  """

  alias Lang.Proxy.Envelope

  @type canonical_request :: %{
          required(:v) => pos_integer(),
          required(:service) => atom(),
          required(:method) => String.t(),
          required(:params) => map(),
          required(:opts) => keyword() | map(),
          required(:meta) => map(),
          required(:stream) => boolean()
        }

  @type canonical_response :: %{
          required(:status) => :ok | :error,
          required(:payload) => map()
        }

  @type capture_record :: %{
          required(:id) => String.t(),
          required(:inserted_at) => DateTime.t(),
          required(:trace_id) => String.t() | nil,
          required(:idempotency_key) => String.t() | nil,
          required(:route_path) => String.t(),
          required(:dependency_refs) => [String.t()],
          required(:canonical_request) => canonical_request(),
          required(:canonical_response) => canonical_response()
        }

  @spec canonical_request(Envelope.t()) :: canonical_request()
  def canonical_request(%Envelope{} = env) do
    %{
      v: env.v,
      service: env.service,
      method: env.method,
      params: env.params || %{},
      opts: env.opts || %{},
      meta: env.meta || %{},
      stream: !!env.stream?
    }
  end

  @spec canonical_response({:ok, any()} | {:error, integer(), String.t(), map()}) :: canonical_response()
  def canonical_response({:ok, payload}), do: %{status: :ok, payload: %{result: payload}}

  def canonical_response({:error, code, message, data}) do
    %{status: :error, payload: %{code: code, message: message, data: data || %{}}}
  end

  @spec normalize_dependency_refs(any()) :: [String.t()]
  def normalize_dependency_refs(refs) when is_list(refs) do
    refs
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  def normalize_dependency_refs(_), do: []
end
