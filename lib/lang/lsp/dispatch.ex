defmodule Lang.LSP.Dispatch do
  @moduledoc "Dispatches LSP JSON-RPC method maps to domain facades."

  def process(%{"method" => method} = msg) do
    case method do
      "lang.think.explain_intent" -> think(:explain_intent, msg)
      "lang.think.find_semantic" -> think(:find_semantic, msg)
      "lang.spatial.map" -> spatial_map(msg)
      "lang.generate.complete_partial" -> generate(:complete_partial, msg)
      _ -> nil
    end
  end

  def process(_), do: nil

  defp think(kind, %{"id" => id, "params" => params}) do
    req_attrs = %{
      kind: kind,
      input: Map.get(params, "input", %{}),
      user_id: Map.get(params, "user_id"),
      project_id: Map.get(params, "project_id"),
      run_id: Map.get(params, "run_id")
    }

    case Lang.ThinkAPI.create_request(req_attrs) do
      {:ok, req} ->
        _ = Lang.ThinkAPI.enqueue_request(req.id)
        %{"jsonrpc" => "2.0", "id" => id, "result" => %{request_id: req.id, status: "queued"}}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp spatial_map(%{"id" => id, "params" => params}) do
    project_id = Map.get(params, "project_id")
    path = Map.get(params, "path")
    _ = Lang.Spatial.ensure_map(project_id, path: path)
    %{"jsonrpc" => "2.0", "id" => id, "result" => %{enqueued: true}}
  end

  defp generate(strategy, %{"id" => id, "params" => params}) do
    req_attrs = %{
      strategy: strategy,
      inputs: Map.get(params, "inputs", %{}),
      boundaries: Map.get(params, "boundaries", %{}),
      user_id: Map.get(params, "user_id"),
      project_id: Map.get(params, "project_id"),
      run_id: Map.get(params, "run_id")
    }

    case Lang.GenerateAPI.create_request(req_attrs) do
      {:ok, req} ->
        _ = Lang.GenerateAPI.enqueue_request(req.id)
        %{"jsonrpc" => "2.0", "id" => id, "result" => %{request_id: req.id, status: "queued"}}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end
end
