defmodule Lang.Think.ThinkFacadesTest do
  use Lang.DataCase, async: false

  alias Lang.Think.{Explainer, Diagnostics, Predictor, Security, Search, Tracer, Result, Request}
  alias Lang.Think.Workers.RequestWorker
  require Ash.Query

  test "explain_intent facade enqueues and worker produces result" do
    {:ok, req} = Explainer.explain_intent(%{input: %{code: "def foo, do: :ok"}})

    assert %Request{id: id, kind: :explain_intent, status: :pending} = req

    :ok = perform_think(req)

    results =
      Result
      |> Ash.Query.filter(request_id == ^id)
      |> Ash.read!()

    assert length(results) == 1
    [res] = results
    assert is_map(res.details)
    assert res.summary =~ "Intent"
  end

  test "diagnose facade and worker writes hints" do
    stack = "(FunctionClauseError) no function clause matching in MyApp.foo/1\n  (ecto) ...\n  (db_connection) ..."
    {:ok, req} = Diagnostics.diagnose(%{input: %{stacktrace: stack}})

    :ok = perform_think(req)

    [res] =
      Result
      |> Ash.Query.filter(request_id == ^req.id)
      |> Ash.read!()

    assert res.summary =~ "Diagnosis"
    assert get_in(res.details, ["hint"]) || get_in(res.details, [:hint])
  end

  test "predict_bugs facade returns MVP signals" do
    {:ok, req} = Predictor.predict_bugs(%{input: %{}})
    :ok = perform_think(req)
    [res] = Result |> Ash.Query.filter(request_id == ^req.id) |> Ash.read!()
    assert res.summary =~ "bug"
  end

  test "security_scan facade queues and completes" do
    {:ok, req} = Security.security_scan(%{input: %{paths: ["lib/"]}})
    :ok = perform_think(req)
    [res] = Result |> Ash.Query.filter(request_id == ^req.id) |> Ash.read!()
    assert res.summary =~ "Security"
  end

  test "find_semantic facade queues and completes" do
    {:ok, req} = Search.find_semantic(%{input: %{query: "foo"}})
    :ok = perform_think(req)
    [res] = Result |> Ash.Query.filter(request_id == ^req.id) |> Ash.read!()
    assert res.summary =~ "find_semantic"
  end

  test "trace_flow facade queues and completes" do
    {:ok, req} = Tracer.trace_flow(%{input: %{from: "a.ex", to: "b.ex"}})
    :ok = perform_think(req)
    [res] = Result |> Ash.Query.filter(request_id == ^req.id) |> Ash.read!()
    assert res.summary =~ "Trace"
  end

  defp perform_think(%Request{id: id}) do
    job = %Oban.Job{args: %{"request_id" => id}}
    case RequestWorker.perform(job) do
      :ok -> :ok
      other -> raise "perform returned #{inspect(other)}"
    end
  end
end

