defmodule Lang.Proxy.CaptureStore do
  @moduledoc """
  In-memory capture storage with bounded retention and indexed lookups.

  Uses ETS with three tables:
  - records by capture id
  - trace_id -> [capture ids]
  - idempotency_key -> [capture ids]
  """

  use GenServer

  alias Lang.Proxy.{CaptureSchema, Envelope, Router}

  @records_table :proxy_capture_records
  @trace_index_table :proxy_capture_trace_index
  @idem_index_table :proxy_capture_idem_index

  @default_max_records 500
  @default_retention_seconds 3600

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@records_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@trace_index_table, [:bag, :named_table, :public, read_concurrency: true])
    :ets.new(@idem_index_table, [:bag, :named_table, :public, read_concurrency: true])
    {:ok, %{max_records: max_records(), retention_seconds: retention_seconds()}}
  end

  @spec put_capture(map()) :: {:ok, map()} | {:error, term()}
  def put_capture(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:put_capture, attrs})

  @spec get_capture(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_capture(id) when is_binary(id) do
    purge_expired()

    case :ets.lookup(@records_table, id) do
      [{^id, record}] -> {:ok, record}
      _ -> {:error, :not_found}
    end
  end

  @spec find_capture(keyword()) :: {:ok, map()} | {:error, :not_found}
  def find_capture(opts) when is_list(opts) do
    purge_expired()

    cond do
      is_binary(opts[:id]) -> get_capture(opts[:id])
      is_binary(opts[:trace_id]) -> fetch_latest_by_index(@trace_index_table, opts[:trace_id])
      is_binary(opts[:idempotency_key]) -> fetch_latest_by_index(@idem_index_table, opts[:idempotency_key])
      true -> {:error, :not_found}
    end
  end

  @spec replay_capture(String.t(), :dry | :strict) :: {:ok, map()} | {:error, term()}
  def replay_capture(id, mode) when mode in [:dry, :strict] do
    with {:ok, capture} <- get_capture(id) do
      case mode do
        :dry ->
          {:ok, %{mode: :dry, replayed: false, capture: capture}}

        :strict ->
          with {:ok, env} <- Envelope.new(capture.canonical_request),
               result <- Router.dispatch(env) do
            actual = CaptureSchema.canonical_response(result)
            expected = capture.canonical_response

            {:ok,
             %{
               mode: :strict,
               replayed: true,
               matched?: actual == expected,
               expected: expected,
               actual: actual,
               capture: capture
             }}
          end
      end
    end
  end

  @impl true
  def handle_call({:put_capture, attrs}, _from, state) do
    now = DateTime.utc_now()
    id = Ecto.UUID.generate()

    record = %{
      id: id,
      inserted_at: now,
      expires_at: DateTime.add(now, state.retention_seconds, :second),
      trace_id: normalize(attrs[:trace_id] || attrs["trace_id"]),
      idempotency_key: normalize(attrs[:idempotency_key] || attrs["idempotency_key"]),
      route_path: to_string(attrs[:route_path] || attrs["route_path"] || "unknown"),
      dependency_refs:
        CaptureSchema.normalize_dependency_refs(attrs[:dependency_refs] || attrs["dependency_refs"]),
      canonical_request: attrs[:canonical_request] || attrs["canonical_request"] || %{},
      canonical_response: attrs[:canonical_response] || attrs["canonical_response"] || %{}
    }

    :ets.insert(@records_table, {id, record})
    maybe_index(@trace_index_table, record.trace_id, id)
    maybe_index(@idem_index_table, record.idempotency_key, id)

    state = enforce_bounds(state)
    {:reply, {:ok, record}, state}
  end

  defp fetch_latest_by_index(table, key) do
    ids = :ets.lookup(table, key) |> Enum.map(fn {_k, id} -> id end)

    ids
    |> Enum.map(fn id -> case :ets.lookup(@records_table, id) do [{^id, rec}] -> rec; _ -> nil end end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> List.first()
    |> case do
      nil -> {:error, :not_found}
      rec -> {:ok, rec}
    end
  end

  defp maybe_index(_table, nil, _id), do: :ok
  defp maybe_index(_table, "", _id), do: :ok
  defp maybe_index(table, key, id), do: :ets.insert(table, {key, id})

  defp normalize(v) when is_binary(v), do: String.trim(v)
  defp normalize(_), do: nil

  defp max_records,
    do: Application.get_env(:lang, :proxy_capture_max_records, @default_max_records)

  defp retention_seconds,
    do: Application.get_env(:lang, :proxy_capture_retention_seconds, @default_retention_seconds)

  defp purge_expired do
    now = DateTime.utc_now()

    for {_id, rec} <- :ets.tab2list(@records_table), DateTime.compare(rec.expires_at, now) == :lt do
      delete_record(rec)
    end

    :ok
  end

  defp enforce_bounds(state) do
    purge_expired()

    count = :ets.info(@records_table, :size)

    if count > state.max_records do
      drop = count - state.max_records

      @records_table
      |> :ets.tab2list()
      |> Enum.map(fn {_id, rec} -> rec end)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})
      |> Enum.take(drop)
      |> Enum.each(&delete_record/1)
    end

    state
  end

  defp delete_record(rec) do
    :ets.delete(@records_table, rec.id)
    maybe_delete_index(@trace_index_table, rec.trace_id, rec.id)
    maybe_delete_index(@idem_index_table, rec.idempotency_key, rec.id)
  end

  defp maybe_delete_index(_table, nil, _id), do: :ok
  defp maybe_delete_index(_table, "", _id), do: :ok
  defp maybe_delete_index(table, key, id), do: :ets.delete_object(table, {key, id})
end
