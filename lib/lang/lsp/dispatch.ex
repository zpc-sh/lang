defmodule Lang.LSP.Dispatch do
  @moduledoc "Dispatches LSP JSON-RPC method maps to domain facades."

  @not_impl_methods ~w(
    lang.think.suggest_refactor
    lang.generate.from_diagram
    lang.generate.compose
    lang.generate.terraform
    lang.generate.ci_pipeline
    lang.generate.gitops
    lang.generate.service_mesh
    lang.generate.api_gateway
    lang.generate.load_balancer
    lang.generate.monitoring
    lang.generate.agent.documentation
    lang.generate.agent.devops
    lang.generate.cognitive.integration
    lang.generate.cognitive.architecture
    lang.generate.maintain_style
    lang.generate.learn_patterns
    lang.spatial.waypoint_set
    lang.spatial.waypoint_jump

    lang.timeline.evolution
    lang.timeline.blame_semantic
    lang.timeline.predict_changes
    lang.timeline.find_decisions
    lang.timeline.regression_risk
  )

  def process(%{"method" => method} = msg) do
    case method do
      "lang.think.explain_intent" -> think(:explain_intent, msg)
      "lang.think.explain_why" -> think(:explain_why, msg)
      "lang.think.explain_how" -> think(:explain_how, msg)
      "lang.think.diagnose" -> think(:diagnose, msg)
      "lang.think.predict_bugs" -> think(:predict_bugs, msg)
      "lang.think.predict_performance" -> think(:predict_performance, msg)
      "lang.think.security_scan" -> think(:security_scan, msg)
      "lang.think.find_semantic" -> think(:find_semantic, msg)
      "lang.think.find_similar" -> think(:find_similar, msg)
      "lang.think.trace_flow" -> think(:trace_flow, msg)
      "lang.think.generate_tests" -> think(:generate_tests, msg)
      "lang.think.review_code" -> think(:review_code, msg)
      "lang.think.estimate_complexity" -> think(:estimate_complexity, msg)
      "lang.spatial.map" -> spatial_map(msg)
      "lang.spatial.traverse" -> spatial_traverse(msg)
      "lang.spatial.trace_path" -> spatial_trace_path(msg)
      "lang.spatial.find_related" -> spatial_find_related(msg)
      "lang.capabilities" -> capabilities(msg)
      "lang.generate.complete_partial" -> generate(:complete_partial, msg)
      "lang.generate.from_spec" -> generate(:from_spec, msg)
      "lang.generate.from_tests" -> generate(:from_tests, msg)
      "lang.generate.variations" -> generate(:variations, msg)
      "lang.generate.optimize" -> generate(:optimize, msg)
      "lang.generate.parallelize" -> generate(:parallelize, msg)
      "lang.generate.migrate" -> generate(:migrate, msg)
      "lang.generate.dockerfile" -> generate(:dockerfile, msg)
      "lang.generate.agent.implementation" -> generate(:agent_implementation, msg)
      "lang.generate.agent.testing" -> generate(:agent_testing, msg)
      "lang.generate.cognitive.simple" -> generate(:cognitive_simple, msg)
      "lang.generate.cognitive.feature" -> generate(:cognitive_feature, msg)
      "lang.tokens.estimate" -> tokens(:estimate, msg)
      "lang.tokens.compress" -> tokens(:compress, msg)
      "lang.tokens.filter" -> tokens(:filter, msg)
      "lang.tokens.stream" -> tokens(:stream, msg)
      "lang.tokens.cache_strategy" -> tokens(:cache_strategy, msg)
      "lang.query.natural" -> query(:natural, msg)
      "lang.query.impact" -> query(:impact, msg)
      "lang.query.dependency" -> query(:dependency, msg)
      "lang.query.ownership" -> query(:ownership, msg)
      "lang.timeline.create" -> timeline(:create, msg)
      "lang.timeline.add_state" -> timeline(:add_state, msg)
      "lang.timeline.navigate" -> timeline(:navigate, msg)
      "lang.timeline.branch" -> timeline(:branch, msg)
      "lang.timeline.diff" -> timeline(:diff, msg)
      "lang.timeline.replay" -> timeline(:replay, msg)
      "lang.timeline.analyze" -> timeline(:analyze, msg)
      "lang.agent.spawn" -> agent_spawn(msg)
      "lang.agent.delegate" -> agent_delegate(msg)
      "lang.agent.coordinate" -> agent_coordinate(msg)
      "lang.agent.merge_results" -> agent_merge_results(msg)
      "lang.agent.terminate" -> agent_terminate(msg)
      "lang.agent.get_status" -> agent_get_status(msg)
      "lang.agent.scan" -> agent_scan(msg)
      "lang.agent.verify_profile" -> agent_verify_profile(msg)
      "lang.agent.detect_rogue" -> agent_detect_rogue(msg)
      "lang.agent.quarantine" -> agent_quarantine(msg)
      "lang.agent.behavior_baseline" -> agent_behavior_baseline(msg)
      "lang.agent.anomaly_score" -> agent_anomaly_score(msg)
      "lang.agent.trust_level" -> agent_trust_level(msg)
      "lang.agent.audit_trail" -> agent_audit_trail(msg)
      "lang.agent.track_usage" -> agent_track_usage(msg)
      "lang.agent.limit_resources" -> agent_limit_resources(msg)
      "lang.agent.monitor_performance" -> agent_monitor_performance(msg)
      "lang.metrics.tokens" -> metrics_tokens(msg)
      m when m in @not_impl_methods -> not_implemented(msg)
      _ -> nil
    end
  end

  def process(_), do: nil

  defp think(kind, %{"id" => id, "params" => params, "method" => method}) do
    # If client requests realtime/provider handling, route to providers; else enqueue
    if realtime_request?(params) do
      router_opts = provider_opt(params)

      case Lang.Providers.Router.route_request(method, params, router_opts) do
        {:ok, result} ->
          %{"jsonrpc" => "2.0", "id" => id, "result" => result}

        {:error, reason} ->
          %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
      end
    else
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
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => %{code: -32602, message: "project_id required"}
        }

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
            {:ok, result} ->
              %{"jsonrpc" => "2.0", "id" => id, "result" => result}

            {:error, reason} ->
              %{
                "jsonrpc" => "2.0",
                "id" => id,
                "error" => %{code: -32000, message: inspect(reason)}
              }
          end
        else
          {:error, :invalid_int} ->
            %{
              "jsonrpc" => "2.0",
              "id" => id,
              "error" => %{code: -32602, message: "invalid depth param"}
            }
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
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => %{code: -32602, message: "project_id required"}
        }

      is_nil(from) or from == "" or is_nil(to) or to == "" ->
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => %{code: -32602, message: "from and to required"}
        }

      true ->
        spec = %{from: from, to: to}
        opts = []
        opts = if language, do: Keyword.put(opts, :language, language), else: opts
        opts = if types, do: Keyword.put(opts, :types, types), else: opts

        case Lang.Spatial.Mapper.trace_path(project_id, spec, opts) do
          {:ok, result} ->
            %{"jsonrpc" => "2.0", "id" => id, "result" => result}

          {:error, reason} ->
            %{
              "jsonrpc" => "2.0",
              "id" => id,
              "error" => %{code: -32000, message: inspect(reason)}
            }
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
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => %{code: -32602, message: "project_id required"}
        }

      is_nil(file) or file == "" ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32602, message: "file required"}}

      true ->
        criteria = %{file: file}
        opts = []
        opts = if language, do: Keyword.put(opts, :language, language), else: opts
        opts = if types, do: Keyword.put(opts, :types, types), else: opts
        opts = if top_n, do: Keyword.put(opts, :top_n, top_n), else: opts

        case Lang.Spatial.Mapper.find_related(project_id, criteria, opts) do
          {:ok, result} ->
            %{"jsonrpc" => "2.0", "id" => id, "result" => result}

          {:error, reason} ->
            %{
              "jsonrpc" => "2.0",
              "id" => id,
              "error" => %{code: -32000, message: inspect(reason)}
            }
        end
    end
  end

  defp query(kind, %{"id" => id, "params" => params}) do
    req_attrs = %{
      kind: kind,
      query: Map.get(params, "query", ""),
      context: Map.get(params, "context", %{}),
      scope: Map.get(params, "scope"),
      target_element: Map.get(params, "target_element"),
      change_description: Map.get(params, "change_description"),
      analysis_depth: parse_atom(Map.get(params, "analysis_depth")),
      use_graph_reasoning: Map.get(params, "use_graph_reasoning", true),
      provider_preference: Map.get(params, "provider_preference"),
      user_id: Map.get(params, "user_id"),
      project_id: Map.get(params, "project_id"),
      run_id: Map.get(params, "run_id"),
      metadata: Map.get(params, "metadata", %{})
    }

    case Lang.Query.Request.create_enqueued(req_attrs) do
      {:ok, req} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => %{request_id: req.id, status: "queued"}}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp capabilities(%{"id" => id}) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "implemented" => [
          "lang.think.explain_intent",
          "lang.think.explain_why",
          "lang.think.explain_how",
          "lang.think.diagnose",
          "lang.think.predict_bugs",
          "lang.think.predict_performance",
          "lang.think.security_scan",
          "lang.think.find_semantic",
          "lang.think.find_similar",
          "lang.think.trace_flow",
          "lang.think.generate_tests",
          "lang.think.review_code",
          "lang.think.estimate_complexity",
          "lang.generate.complete_partial",
          "lang.generate.from_spec",
          "lang.generate.from_tests",
          "lang.generate.variations",
          "lang.generate.optimize",
          "lang.generate.parallelize",
          "lang.generate.migrate",
          "lang.generate.dockerfile",
          "lang.generate.agent.implementation",
          "lang.generate.agent.testing",
          "lang.generate.cognitive.simple",
          "lang.generate.cognitive.feature",
          "lang.spatial.map",
          "lang.spatial.traverse",
          "lang.spatial.trace_path",
          "lang.spatial.find_related",
          "lang.tokens.estimate",
          "lang.tokens.compress",
          "lang.tokens.filter",
          "lang.tokens.stream",
          "lang.tokens.cache_strategy",
          "lang.query.natural",
          "lang.query.impact",
          "lang.query.dependency",
          "lang.query.ownership",
          "lang.metrics.tokens"
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

  defp parse_atom(nil), do: nil
  defp parse_atom(val) when is_atom(val), do: val

  defp parse_atom(val) when is_binary(val) do
    case val do
      "shallow" -> :shallow
      "standard" -> :standard
      "deep" -> :deep
      _ -> :standard
    end
  end

  defp parse_atom(_), do: :standard

  defp realtime_request?(params) do
    case {Map.get(params, "mode"), Map.get(params, "provider")} do
      {mode, _} when mode in ["realtime", "sync", true] -> true
      {_, prov} when prov in ["xai", "openai", "anthropic"] -> true
      _ -> false
    end
  end

  defp provider_opt(%{"provider" => p}) do
    case p do
      "xai" -> [provider: :xai]
      "openai" -> [provider: :openai]
      "anthropic" -> [provider: :anthropic]
      _ -> []
    end
  end

  defp provider_opt(_), do: []

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

  # === Agent namespace ===
  defp agent_spawn(%{"id" => id, "params" => params}) do
    caps = params["capabilities"] || []
    constraints = params["constraints"] || %{}

    ctx = %{
      session_id: Map.get(params, "session_id"),
      spawned_by: Map.get(params, "user_id", "system"),
      metadata: Map.get(params, "metadata", %{})
    }

    case Lang.Agent.Lifecycle.spawn(caps, constraints, ctx) do
      {:ok, agent} ->
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => %{agent_id: agent.id, status: to_string(agent.state)}
        }

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp agent_delegate(%{"id" => id, "params" => params}) do
    agent_id = Map.get(params, "agent_id")
    task = Map.get(params, "task", %{}) |> atomize_keys()

    case Lang.Agent.Lifecycle.delegate(agent_id, task) do
      {:ok, result} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => result}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp agent_coordinate(%{"id" => id, "params" => params}) do
    agent_ids = Map.get(params, "agent_ids", [])
    task = Map.get(params, "task", %{}) |> atomize_keys()

    case Lang.Agent.Lifecycle.coordinate(agent_ids, task) do
      {:ok, result} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => result}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp agent_merge_results(%{"id" => id, "params" => params}) do
    results = Map.get(params, "results", [])

    case Lang.Agent.Lifecycle.merge_results(results) do
      {:ok, merged} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => merged}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp agent_terminate(%{"id" => id, "params" => params}) do
    agent_id = Map.get(params, "agent_id")
    reason = Map.get(params, "reason", "normal")

    case Lang.Agent.Lifecycle.terminate(agent_id, reason) do
      {:ok, final_state} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => final_state}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp agent_get_status(%{"id" => id, "params" => params}) do
    agent_id = Map.get(params, "agent_id")

    case Lang.Agent.Lifecycle.get_status(agent_id) do
      {:ok, status} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => status}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp agent_scan(%{"id" => id, "params" => params}) do
    agent_id = Map.get(params, "agent_id")
    ctx = Map.get(params, "scanner_context", %{})

    case Lang.Agent.Security.scan(agent_id, ctx) do
      {:ok, res} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => res}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp agent_verify_profile(%{"id" => id, "params" => params}) do
    agent_id = Map.get(params, "agent_id")
    expected = Map.get(params, "expected_profile", :auto) |> to_expected_profile()

    case Lang.Agent.Security.verify_profile(agent_id, expected) do
      {:ok, res} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => res}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp agent_detect_rogue(%{"id" => id, "params" => params}) do
    agent_id = Map.get(params, "agent_id")
    ctx = Map.get(params, "detection_context", %{})

    case Lang.Agent.Security.detect_rogue(agent_id, ctx) do
      {:ok, class} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => %{classification: class}}

      {:ok, class, details} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => %{classification: class, details: details}}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp agent_quarantine(%{"id" => id, "params" => params}) do
    agent_id = Map.get(params, "agent_id")
    reason = Map.get(params, "reason", "behavioral_anomaly")
    severity = Map.get(params, "severity", "medium") |> to_severity()

    case Lang.Agent.Security.quarantine(agent_id, reason, severity) do
      {:ok, res} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => res}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp agent_behavior_baseline(%{"id" => id, "params" => params}),
    do: enqueue_agent_job("behavior_baseline", params, id)

  defp agent_anomaly_score(%{"id" => id, "params" => params}),
    do: enqueue_agent_job("anomaly_score", params, id)

  defp agent_trust_level(%{"id" => id, "params" => params}),
    do: enqueue_agent_job("trust_level", params, id)

  defp agent_audit_trail(%{"id" => id, "params" => params}),
    do: enqueue_agent_job("audit_trail", params, id)

  defp agent_track_usage(%{"id" => id, "params" => params}),
    do: enqueue_agent_job("track_usage", params, id)

  defp agent_limit_resources(%{"id" => id, "params" => params}),
    do: enqueue_agent_job("limit_resources", params, id)

  defp agent_monitor_performance(%{"id" => id, "params" => params}),
    do: enqueue_agent_job("monitor_performance", params, id)

  defp enqueue_agent_job(action, params, id) do
    payload =
      %{action: action, params: params}
      |> Map.merge(extract_context(params))

    job = Lang.Workers.AgentTaskWorker.new(payload, queue: :agent)

    case Oban.insert(job) do
      {:ok, job} ->
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => %{status: "queued", job_id: job.id, action: action}
        }

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp extract_context(params) when is_map(params) do
    %{
      user_id: Map.get(params, "user_id"),
      session_id: Map.get(params, "session_id"),
      project_id: Map.get(params, "project_id"),
      request_id: Map.get(params, "request_id")
    }
  end

  defp extract_context(_), do: %{}

  defp to_severity(v) when is_atom(v), do: v

  defp to_severity(v) when is_binary(v) do
    case String.downcase(v) do
      "low" -> :low
      "medium" -> :medium
      "high" -> :high
      "critical" -> :critical
      _ -> :medium
    end
  end

  defp to_expected_profile(v) when is_atom(v), do: v

  defp to_expected_profile(v) when is_binary(v) do
    case String.downcase(v) do
      "auto" -> :auto
      "normal" -> :normal
      "suspicious" -> :suspicious
      "rogue" -> :rogue
      _ -> :auto
    end
  end

  defp atomize_keys(map) when is_map(map) do
    for {k, v} <- map, into: %{}, do: {to_atom_safe(k), v}
  end

  defp to_atom_safe(k) when is_atom(k), do: k

  defp to_atom_safe(k) when is_binary(k) do
    try do
      String.to_existing_atom(k)
    rescue
      ArgumentError -> String.to_atom(k)
    end
  end

  defp tokens(kind, %{"id" => id, "params" => params}) do
    req_attrs = %{
      kind: kind,
      input: Map.get(params, "input", %{}),
      model_type: Map.get(params, "model_type"),
      target_ratio: parse_decimal(Map.get(params, "target_ratio")),
      user_id: Map.get(params, "user_id"),
      project_id: Map.get(params, "project_id"),
      run_id: Map.get(params, "run_id"),
      metadata: Map.get(params, "metadata", %{})
    }

    case Lang.Tokens.Request.create_enqueued(req_attrs) do
      {:ok, req} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => %{request_id: req.id, status: "queued"}}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(val) when is_number(val), do: Decimal.from_float(val)

  defp parse_decimal(val) when is_binary(val) do
    case Decimal.parse(val) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp parse_decimal(%Decimal{} = d), do: d
  defp parse_decimal(_), do: nil

  defp timeline(operation, %{"id" => id, "params" => params}) do
    with :ok <- realtime_request?(params) do
      case operation do
        :create ->
          content_id = Map.get(params, "content_id") || "default_#{:rand.uniform(10000)}"
          initial_state = Map.get(params, "initial_state", %{})
          metadata = Map.get(params, "metadata", %{})

          case Lang.Timeline.Core.create_timeline(content_id, initial_state, metadata) do
            {:ok, timeline_id} ->
              {:ok, id, %{timeline_id: timeline_id, content_id: content_id, created: true}}

            {:error, reason} ->
              {:error, id, -32603, "Timeline creation failed", %{reason: inspect(reason)}}
          end

        :add_state ->
          timeline_id = Map.get(params, "timeline_id")
          state_data = Map.get(params, "state_data", %{})
          metadata = Map.get(params, "metadata", %{})

          if timeline_id do
            case Lang.Timeline.Core.add_state(timeline_id, state_data, metadata) do
              {:ok, state_id} ->
                {:ok, id, %{timeline_id: timeline_id, state_id: state_id, added: true}}

              {:error, reason} ->
                {:error, id, -32603, "Add state failed", %{reason: inspect(reason)}}
            end
          else
            {:error, id, -32602, "Missing timeline_id parameter", %{}}
          end

        :navigate ->
          timeline_id = Map.get(params, "timeline_id")
          state_id = Map.get(params, "state_id")

          if timeline_id && state_id do
            case Lang.Timeline.Core.navigate_to_state(timeline_id, state_id) do
              {:ok, result} ->
                {:ok, id, %{timeline_id: timeline_id, current_state: state_id, navigated: true}}

              {:error, reason} ->
                {:error, id, -32603, "Navigation failed", %{reason: inspect(reason)}}
            end
          else
            {:error, id, -32602, "Missing timeline_id or state_id parameter", %{}}
          end

        :branch ->
          timeline_id = Map.get(params, "timeline_id")
          from_state_id = Map.get(params, "from_state_id")
          branch_name = Map.get(params, "branch_name")

          if timeline_id && from_state_id && branch_name do
            case Lang.Timeline.Core.create_branch(timeline_id, from_state_id, branch_name) do
              {:ok, result} ->
                {:ok, id, %{timeline_id: timeline_id, branch_name: branch_name, created: true}}

              {:error, reason} ->
                {:error, id, -32603, "Branch creation failed", %{reason: inspect(reason)}}
            end
          else
            {:error, id, -32602, "Missing required parameters for branch creation", %{}}
          end

        :diff ->
          timeline_id = Map.get(params, "timeline_id")
          from_state_id = Map.get(params, "from_state_id")
          to_state_id = Map.get(params, "to_state_id")

          if timeline_id && from_state_id && to_state_id do
            case Lang.Timeline.Core.diff_states(timeline_id, from_state_id, to_state_id) do
              {:ok, diff} ->
                {:ok, id, diff}

              {:error, reason} ->
                {:error, id, -32603, "Diff calculation failed", %{reason: inspect(reason)}}
            end
          else
            {:error, id, -32602, "Missing required parameters for diff", %{}}
          end

        :replay ->
          timeline_id = Map.get(params, "timeline_id")
          from_state_id = Map.get(params, "from_state_id")
          to_state_id = Map.get(params, "to_state_id")
          options = Map.get(params, "options", %{})

          if timeline_id && from_state_id && to_state_id do
            case Lang.Timeline.Core.replay_timeline(
                   timeline_id,
                   from_state_id,
                   to_state_id,
                   options
                 ) do
              {:ok, replay_data} ->
                {:ok, id, replay_data}

              {:error, reason} ->
                {:error, id, -32603, "Replay failed", %{reason: inspect(reason)}}
            end
          else
            {:error, id, -32602, "Missing required parameters for replay", %{}}
          end

        :analyze ->
          timeline_id = Map.get(params, "timeline_id")

          if timeline_id do
            case Lang.Timeline.Core.analyze_timeline(timeline_id) do
              {:ok, analysis} ->
                {:ok, id, analysis}

              {:error, reason} ->
                {:error, id, -32603, "Timeline analysis failed", %{reason: inspect(reason)}}
            end
          else
            {:error, id, -32602, "Missing timeline_id parameter", %{}}
          end
      end
    end
  end

  defp metrics_tokens(%{"id" => id, "params" => params}) do
    case Lang.Metrics.Tokens.summary(params || %{}) do
      {:ok, summary} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => summary}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end
end
