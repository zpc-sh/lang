defmodule Lang.LSP.Dispatch do
  @moduledoc "Dispatches LSP JSON-RPC method maps to domain facades."

  @not_impl_methods ~w(
    lang.think.explain_why
    lang.think.explain_how
    lang.think.diagnose
    lang.think.predict_bugs
    lang.think.predict_performance
    lang.think.security_scan
    lang.think.find_similar
    lang.think.trace_flow
    lang.think.suggest_refactor
    lang.think.generate_tests
    lang.think.review_code
    lang.think.estimate_complexity
    lang.generate.from_spec
    lang.generate.from_tests
    lang.generate.from_diagram
    lang.generate.variations
    lang.generate.optimize
    lang.generate.parallelize
    lang.generate.migrate
    lang.generate.dockerfile
    lang.generate.compose
    lang.generate.kubernetes
    lang.generate.terraform
    lang.generate.ci_pipeline
    lang.generate.gitops
    lang.generate.service_mesh
    lang.generate.api_gateway
    lang.generate.load_balancer
    lang.generate.monitoring
    lang.generate.agent.implementation
    lang.generate.agent.testing
    lang.generate.agent.documentation
    lang.generate.agent.devops
    lang.generate.cognitive.simple
    lang.generate.cognitive.feature
    lang.generate.cognitive.integration
    lang.generate.cognitive.architecture
    lang.generate.from_patterns
    lang.generate.respect_boundaries
    lang.generate.maintain_style
    lang.generate.learn_patterns
    lang.spatial.traverse
    lang.spatial.waypoint_set
    lang.spatial.waypoint_jump
    lang.spatial.trace_path
    lang.spatial.find_related
    lang.agent.spawn
    lang.agent.delegate
    lang.agent.coordinate
    lang.agent.merge_results
    lang.agent.terminate
    lang.agent.get_status
    lang.agent.scan
    lang.agent.verify_profile
    lang.agent.detect_rogue
    lang.agent.quarantine
    lang.agent.behavior_baseline
    lang.agent.anomaly_score
    lang.agent.trust_level
    lang.agent.audit_trail
    lang.agent.track_usage
    lang.agent.limit_resources
    lang.agent.monitor_performance
    lang.timeline.evolution
    lang.timeline.blame_semantic
    lang.timeline.predict_changes
    lang.timeline.find_decisions
    lang.timeline.regression_risk
  )

  def process(%{"method" => method} = msg) do
    case method do
      "lang.think.explain_intent" -> think(:explain_intent, msg)
      "lang.think.find_semantic" -> think(:find_semantic, msg)
      "lang.spatial.map" -> spatial_map(msg)
      "lang.spatial.traverse" -> spatial_traverse(msg)
      "lang.spatial.trace_path" -> spatial_trace_path(msg)
      "lang.spatial.find_related" -> spatial_find_related(msg)
      "lang.capabilities" -> capabilities(msg)
      "lang.generate.complete_partial" -> generate(:complete_partial, msg)
      m when m in @not_impl_methods -> not_implemented(msg)
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

    case Lang.Think.Request.create_enqueued(req_attrs) do
      {:ok, req} ->
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

    case Lang.Generate.Request.create_enqueued(req_attrs) do
      {:ok, req} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => %{request_id: req.id, status: "queued"}}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp spatial_traverse(%{"id" => id, "params" => params}) do
    project_id = Map.get(params, "project_id")
    depth_param = Map.get(params, "depth", 3)
    start_file = Map.get(params, "file")
    language = Map.get(params, "language")
    types = Map.get(params, "types")
    kinds = Map.get(params, "kinds")

    cond do
      is_nil(project_id) or project_id == "" ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32602, message: "project_id required"}}

      is_nil(start_file) or start_file == "" ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32602, message: "file required"}}

      true ->
    with {:ok, depth} <- parse_nonneg_int(depth_param) do
      opts = [depth: depth]
      opts = if start_file, do: Keyword.put(opts, :file, start_file), else: opts
      opts = if language, do: Keyword.put(opts, :language, language), else: opts
      opts = if types, do: Keyword.put(opts, :types, types), else: opts
      opts = if kinds, do: Keyword.put(opts, :kinds, kinds), else: opts

      case Lang.Spatial.Mapper.traverse(project_id, opts) do
        {:ok, result} -> %{"jsonrpc" => "2.0", "id" => id, "result" => result}
        {:error, reason} -> %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
      end
    else
      {:error, :invalid_int} ->
      %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32602, message: "invalid depth param"}}
    end
    end
  end

  defp spatial_trace_path(%{"id" => id, "params" => params}) do
    project_id = Map.get(params, "project_id")
    from = Map.get(params, "from")
    to = Map.get(params, "to")
    language = Map.get(params, "language")
    types = Map.get(params, "types")

    cond do
      is_nil(project_id) or project_id == "" ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32602, message: "project_id required"}}

      is_nil(from) or from == "" or is_nil(to) or to == "" ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32602, message: "from and to required"}}

      true ->
    spec = %{from: from, to: to}
    opts = []
    opts = if language, do: Keyword.put(opts, :language, language), else: opts
    opts = if types, do: Keyword.put(opts, :types, types), else: opts

    case Lang.Spatial.Mapper.trace_path(project_id, spec, opts) do
      {:ok, result} -> %{"jsonrpc" => "2.0", "id" => id, "result" => result}
      {:error, reason} -> %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
    end
  end

  defp spatial_find_related(%{"id" => id, "params" => params}) do
    project_id = Map.get(params, "project_id")
    file = Map.get(params, "file")
    language = Map.get(params, "language")
    types = Map.get(params, "types")
    top_n = Map.get(params, "top_n")

    cond do
      is_nil(project_id) or project_id == "" ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32602, message: "project_id required"}}

      is_nil(file) or file == "" ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32602, message: "file required"}}

      true ->
    criteria = %{file: file}
    opts = []
    opts = if language, do: Keyword.put(opts, :language, language), else: opts
    opts = if types, do: Keyword.put(opts, :types, types), else: opts
    opts = if top_n, do: Keyword.put(opts, :top_n, top_n), else: opts

    case Lang.Spatial.Mapper.find_related(project_id, criteria, opts) do
      {:ok, result} -> %{"jsonrpc" => "2.0", "id" => id, "result" => result}
      {:error, reason} -> %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
    end
  end

  defp capabilities(%{"id" => id}) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "implemented" => [
          "lang.think.explain_intent",
          "lang.think.find_semantic",
          "lang.generate.complete_partial",
          "lang.spatial.map",
          "lang.spatial.traverse",
          "lang.spatial.trace_path",
          "lang.spatial.find_related"
        ],
        "planned" => @not_impl_methods
      }
    }
  end

  defp parse_nonneg_int(val) when is_integer(val) and val >= 0, do: {:ok, val}
  defp parse_nonneg_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {i, ""} when i >= 0 -> {:ok, i}
      _ -> {:error, :invalid_int}
    end
  end
  defp parse_nonneg_int(_), do: {:error, :invalid_int}

  defp not_implemented(%{"id" => id, "method" => method}) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => -32601,
        "message" => "Method not implemented",
        "data" => %{method: method}
      }
    }
  end

  defp not_implemented(_), do: nil
end
