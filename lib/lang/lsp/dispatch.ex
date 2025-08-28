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
      # Filesystem operations
      "lang.fs.scan" -> fs_scan(msg)
      "lang.fs.search" -> fs_search(msg)
      "lang.fs.search_code" -> fs_search_code(msg)
      "lang.fs.preview" -> fs_preview(msg)
      "lang.fs.watch" -> fs_watch(msg)
      # Storage operations
      "lang.storage.create_session" -> storage_create_session(msg)
      "lang.storage.get_session" -> storage_get_session(msg)
      "lang.storage.close_session" -> storage_close_session(msg)
      "lang.storage.sync_session" -> storage_sync_session(msg)
      "lang.storage.update_user_context" -> storage_update_user_context(msg)
      "lang.storage.get_user_context" -> storage_get_user_context(msg)
      "lang.storage.store_patterns" -> storage_store_patterns(msg)
      "lang.storage.get_patterns" -> storage_get_patterns(msg)
      "lang.storage.search_patterns" -> storage_search_patterns(msg)
      # Analysis operations
      "lang.analyze.document" -> analyze_document(msg)
      "lang.analyze.batch" -> analyze_batch(msg)
      "lang.analyze.stream" -> analyze_stream(msg)
      # Parser operations
      "lang.parser.parse" -> parser_parse(msg)
      "lang.parser.parse_batch" -> parser_parse_batch(msg)
      "lang.parser.parse_stream" -> parser_parse_stream(msg)
      "lang.parser.detect_format" -> parser_detect_format(msg)
      # Graph operations
      "lang.graph.build" -> graph_build(msg)
      "lang.graph.update" -> graph_update(msg)
      "lang.graph.traverse" -> graph_traverse(msg)
      "lang.graph.query" -> graph_query(msg)
      "lang.graph.visualize" -> graph_visualize(msg)
      # Security operations
      "lang.security.validate" -> security_validate(msg)
      "lang.security.sanitize" -> security_sanitize(msg)
      "lang.security.rate_limit" -> security_rate_limit(msg)
      # Metrics operations (beyond tokens)
      "lang.metrics.performance" -> metrics_performance(msg)
      "lang.metrics.usage" -> metrics_usage(msg)
      "lang.metrics.agent_efficiency" -> metrics_agent_efficiency(msg)
      # Orchestration operations
      "lang.orchestration.start" -> orchestration_start(msg)
      "lang.orchestration.status" -> orchestration_status(msg)
      "lang.orchestration.cancel" -> orchestration_cancel(msg)
      # Workspace operations
      "lang.workspace.create" -> workspace_create(msg)
      "lang.workspace.save" -> workspace_save(msg)
      "lang.workspace.load" -> workspace_load(msg)
      "lang.workspace.context" -> workspace_context(msg)
      # MCP operations
      "mcp.connection.create" -> mcp_connection_create(msg)
      "mcp.connection.destroy" -> mcp_connection_destroy(msg)
      "mcp.connection.status" -> mcp_connection_status(msg)
      # RPC operations
      "rpc.initialize" -> rpc_initialize(msg)
      "rpc.shutdown" -> rpc_shutdown(msg)
      "rpc.ping" -> rpc_ping(msg)
      m when m in @not_impl_methods -> not_implemented(msg)
      _ -> nil
    end
  end

  def process(_), do: nil

  # ----------------------------------------------------------------------------
  # Minimal FS handlers (stubs route to native NIFs when possible)
  # ----------------------------------------------------------------------------
  defp fs_scan(%{"id" => id, "params" => %{"path" => path} = params}) do
    opts = [max_depth: Map.get(params, "max_depth", 10)]

    result =
      case Lang.Native.FSScanner.scan(path, opts) do
        {:ok, res} -> {:ok, res}
        {:error, reason} -> {:error, reason}
      end

    wrap_result(id, result)
  end

  defp fs_search(%{"id" => id, "params" => %{"path" => path, "query" => query} = params}) do
    opts = [max_results: Map.get(params, "max_results", 100)]
    result = Lang.Native.FSScanner.search(path, query, opts)
    wrap_result(id, result)
  end

  defp fs_search_code(%{
         "id" => id,
         "params" => %{"path" => path, "language" => lang, "pattern" => pat} = params
       }) do
    opts = [
      max_results: Map.get(params, "max_results", 100),
      max_depth: Map.get(params, "max_depth", 15)
    ]

    result = Lang.Native.FSScanner.search_code(path, lang, pat, opts)
    wrap_result(id, result)
  end

  defp fs_preview(%{"id" => id, "params" => %{"path" => path} = params}) do
    max_lines = Map.get(params, "max_lines", 200)

    result =
      case Lang.Native.FSScanner.preview(path, max_lines: max_lines) do
        {:ok, lines} when is_list(lines) -> {:ok, Enum.join(lines, "\n")}
        other -> other
      end

    wrap_result(id, result)
  end

  defp fs_watch(%{"id" => id}) do
    wrap_result(id, {:error, :not_implemented})
  end

  defp wrap_result(id, {:ok, data}), do: %{"jsonrpc" => "2.0", "id" => id, "result" => data}

  defp wrap_result(id, {:error, reason}),
    do: %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}

  # ----------------------------------------------------------------------------
  # Minimal Storage stubs
  # ----------------------------------------------------------------------------
  defp storage_create_session(%{"id" => id, "params" => %{"project_id" => project_id} = params}) do
    session_id = Ecto.UUID.generate()
    metadata = Map.get(params, "metadata", %{})

    session = %{
      id: session_id,
      project_id: project_id,
      metadata: metadata,
      created_at: DateTime.utc_now()
    }

    :ok = Lang.InMemory.Store.put(:storage_sessions, session_id, session)
    wrap_result(id, {:ok, session})
  end

  defp storage_get_session(%{"id" => id, "params" => %{"session_id" => session_id}}) do
    case Lang.InMemory.Store.get(:storage_sessions, session_id) do
      nil -> wrap_result(id, {:error, :not_found})
      session -> wrap_result(id, {:ok, session})
    end
  end

  defp storage_close_session(%{"id" => id, "params" => %{"session_id" => session_id}}) do
    :ok = Lang.InMemory.Store.delete(:storage_sessions, session_id)
    wrap_result(id, {:ok, %{closed: true, session_id: session_id}})
  end

  defp storage_sync_session(%{"id" => id, "params" => %{"session_id" => session_id}}) do
    case Lang.InMemory.Store.get(:storage_sessions, session_id) do
      nil -> wrap_result(id, {:error, :not_found})
      session -> wrap_result(id, {:ok, %{synced: true, session: session}})
    end
  end

  defp storage_update_user_context(%{"id" => id, "params" => %{"user_id" => user_id, "context" => context}}) do
    :ok = Lang.InMemory.Store.put(:user_contexts, user_id, context)
    wrap_result(id, {:ok, %{updated: true, user_id: user_id}})
  end

  defp storage_get_user_context(%{"id" => id, "params" => %{"user_id" => user_id}}) do
    ctx = Lang.InMemory.Store.get(:user_contexts, user_id, %{})
    wrap_result(id, {:ok, %{user_id: user_id, context: ctx}})
  end

  defp storage_store_patterns(%{"id" => id, "params" => %{"patterns" => patterns}}) do
    pattern_ids =
      Enum.map(patterns, fn p ->
        id = Ecto.UUID.generate()
        :ok = Lang.InMemory.Store.put(:patterns, id, p)
        id
      end)
    wrap_result(id, {:ok, %{stored: length(patterns), pattern_ids: pattern_ids}})
  end

  defp storage_get_patterns(%{"id" => id, "params" => %{"pattern_ids" => pattern_ids}}) do
    patterns = Enum.map(pattern_ids, fn pid -> %{id: pid, pattern: Lang.InMemory.Store.get(:patterns, pid)} end)
    wrap_result(id, {:ok, %{patterns: patterns}})
  end

  defp storage_search_patterns(%{"id" => id, "params" => %{"query" => query}}) do
    all = Lang.InMemory.Store.list(:patterns)
    results =
      Enum.filter_map(all, fn {pid, pat} ->
        str = to_string(pat)
        String.contains?(String.downcase(str), String.downcase(query))
      end, fn {pid, pat} -> %{id: pid, pattern: pat, score: 1.0} end)
    wrap_result(id, {:ok, %{patterns: results, total: length(results)}})
  end

  # ----------------------------------------------------------------------------
  # Minimal Analyze/Parser/Graph stubs
  # ----------------------------------------------------------------------------
  defp analyze_document(%{"id" => id, "params" => %{"content" => content} = params}) do
    format = Map.get(params, "format", "text")

    result =
      case Lang.TextIntelligence.AnalysisEngine.analyze_content(content, format) do
        {:ok, analysis} ->
          {:ok,
           %{
             diagnostics: analysis[:diagnostics] || [],
             complexity: analysis[:complexity] || "unknown",
             suggestions: analysis[:suggestions] || [],
             metadata: analysis[:metadata] || %{}
           }}

        {:error, reason} ->
          {:error, reason}
      end

    wrap_result(id, result)
  end

  defp analyze_batch(%{"id" => id, "params" => %{"documents" => docs}}) do
    # Queue batch analysis job
    job = Lang.Workers.AnalysisWorker.new(%{documents: docs}, queue: :analysis)

    case Oban.insert(job) do
      {:ok, job} ->
        wrap_result(id, {:ok, %{status: "queued", job_id: job.id}})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  defp analyze_stream(%{"id" => id, "params" => params}) do
    # Return stream ID for real-time analysis updates
    stream_id = "analysis_#{:erlang.unique_integer([:positive])}"

    # Start streaming analysis in background
    Task.start_link(fn ->
      # This would stream analysis results via PubSub
      Phoenix.PubSub.broadcast(Lang.PubSub, "lsp:analysis:#{stream_id}", {:started, %{}})
    end)

    wrap_result(id, {:ok, %{stream_id: stream_id, status: "streaming"}})
  end

  defp parser_parse(%{"id" => id, "params" => %{"content" => content, "format" => format}}) do
    result =
      case Lang.TextIntelligence.ParserRegistry.parse(content, format) do
        {:ok, ast} ->
          {:ok, %{ast: ast, format: format}}

        {:error, reason} ->
          {:error, reason}
      end

    wrap_result(id, result)
  end

  defp parser_parse_batch(%{"id" => id, "params" => %{"files" => files}}) do
    # Queue batch parsing job
    job = Lang.Workers.ParserWorker.new(%{files: files}, queue: :parsing)

    case Oban.insert(job) do
      {:ok, job} ->
        wrap_result(id, {:ok, %{status: "queued", job_id: job.id}})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  defp parser_parse_stream(%{"id" => id, "params" => params}) do
    stream_id = "parser_#{:erlang.unique_integer([:positive])}"
    wrap_result(id, {:ok, %{stream_id: stream_id, status: "streaming"}})
  end

  defp parser_detect_format(%{"id" => id, "params" => %{"content" => content}}) do
    format = Lang.TextIntelligence.FormatDetector.detect(content)
    wrap_result(id, {:ok, %{format: format}})
  end

  defp graph_build(%{"id" => id, "params" => %{"project_id" => project_id} = params}) do
    # Enqueue graph building job
    job =
      Lang.Workers.GraphBuilder.new(
        %{
          project_id: project_id,
          options: Map.get(params, "options", %{})
        },
        queue: :graph
      )

    case Oban.insert(job) do
      {:ok, job} ->
        wrap_result(id, {:ok, %{status: "building", job_id: job.id}})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  defp graph_update(%{"id" => id, "params" => params}) do
    wrap_result(id, {:error, :not_implemented})
  end

  defp graph_traverse(%{"id" => id, "params" => %{"start_node" => start, "depth" => depth}}) do
    # This would use the knowledge graph to traverse relationships
    wrap_result(id, {:ok, %{nodes: [], edges: [], depth: depth}})
  end

  defp graph_query(%{"id" => id, "params" => %{"query" => query}}) do
    # Graph query would use a graph database or in-memory graph
    wrap_result(id, {:ok, %{results: [], query: query}})
  end

  defp graph_visualize(%{"id" => id, "params" => %{"graph_id" => graph_id}}) do
    # Generate visualization data (nodes, edges, layout)
    wrap_result(
      id,
      {:ok,
       %{
         nodes: [],
         edges: [],
         layout: "force-directed",
         format: "d3"
       }}
    )
  end

  # ----------------------------------------------------------------------------
  # Security operations stubs
  # ----------------------------------------------------------------------------
  defp security_validate(%{"id" => id, "params" => %{"input" => input, "rules" => rules}}) do
    # Validate input against security rules
    result =
      case Lang.Security.Validator.validate(input, rules) do
        :ok -> {:ok, %{valid: true}}
        {:error, violations} -> {:ok, %{valid: false, violations: violations}}
      end

    wrap_result(id, result)
  end

  defp security_sanitize(%{"id" => id, "params" => %{"input" => input, "type" => type}}) do
    sanitized = Lang.Security.Sanitizer.sanitize(input, String.to_atom(type))
    wrap_result(id, {:ok, %{sanitized: sanitized}})
  end

  defp security_rate_limit(%{"id" => id, "params" => %{"user_id" => user_id, "action" => action}}) do
    case Lang.Security.RateLimiter.check(user_id, action) do
      :ok ->
        wrap_result(id, {:ok, %{allowed: true}})

      {:error, :rate_limited} ->
        wrap_result(id, {:ok, %{allowed: false, retry_after: 60}})
    end
  end

  # ----------------------------------------------------------------------------
  # Metrics operations stubs
  # ----------------------------------------------------------------------------
  defp metrics_performance(%{"id" => id, "params" => %{"period" => period}}) do
    # Get performance metrics for the specified period
    metrics = %{
      avg_response_time: 125,
      p95_response_time: 450,
      p99_response_time: 980,
      requests_per_second: 42.5,
      error_rate: 0.02,
      period: period
    }

    wrap_result(id, {:ok, metrics})
  end

  defp metrics_usage(%{"id" => id, "params" => %{"user_id" => user_id} = params}) do
    period = Map.get(params, "period", "24h")

    usage = %{
      api_calls: 1523,
      tokens_used: 125_000,
      storage_mb: 42.5,
      compute_minutes: 180,
      period: period,
      user_id: user_id
    }

    wrap_result(id, {:ok, usage})
  end

  defp metrics_agent_efficiency(%{"id" => id, "params" => %{"agent_id" => agent_id}}) do
    efficiency = %{
      task_completion_rate: 0.95,
      avg_task_duration: 320,
      resource_efficiency: 0.88,
      error_rate: 0.03,
      agent_id: agent_id
    }

    wrap_result(id, {:ok, efficiency})
  end

  # ----------------------------------------------------------------------------
  # Orchestration operations stubs
  # ----------------------------------------------------------------------------
  defp orchestration_start(%{"id" => id, "params" => %{"workflow" => workflow} = params}) do
    # Start orchestration workflow
    case Lang.Orchestration.Master.start_workflow(workflow, params) do
      {:ok, workflow_id} ->
        wrap_result(id, {:ok, %{workflow_id: workflow_id, status: "started"}})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  defp orchestration_status(%{"id" => id, "params" => %{"workflow_id" => workflow_id}}) do
    case Lang.Orchestration.Master.get_status(workflow_id) do
      {:ok, status} ->
        wrap_result(id, {:ok, status})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  defp orchestration_cancel(%{"id" => id, "params" => %{"workflow_id" => workflow_id}}) do
    case Lang.Orchestration.Master.cancel_workflow(workflow_id) do
      :ok ->
        wrap_result(id, {:ok, %{cancelled: true}})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  # ----------------------------------------------------------------------------
  # Workspace operations stubs
  # ----------------------------------------------------------------------------
  defp workspace_create(%{"id" => id, "params" => %{"name" => name} = params}) do
    workspace_id = "workspace_#{:erlang.unique_integer([:positive])}"

    # Store workspace metadata
    workspace = %{
      id: workspace_id,
      name: name,
      root_path: Map.get(params, "root_path"),
      created_at: DateTime.utc_now()
    }

    wrap_result(id, {:ok, workspace})
  end

  defp workspace_save(%{"id" => id, "params" => %{"workspace_id" => workspace_id} = params}) do
    # Save workspace state
    wrap_result(id, {:ok, %{saved: true, workspace_id: workspace_id}})
  end

  defp workspace_load(%{"id" => id, "params" => %{"workspace_id" => workspace_id}}) do
    # Load workspace state
    workspace = %{
      id: workspace_id,
      name: "My Workspace",
      root_path: "/project",
      files: [],
      settings: %{}
    }

    wrap_result(id, {:ok, workspace})
  end

  defp workspace_context(%{"id" => id, "params" => %{"workspace_id" => workspace_id}}) do
    # Get current workspace context
    context = %{
      workspace_id: workspace_id,
      active_files: [],
      recent_commands: [],
      environment: %{},
      capabilities: ["analysis", "generation", "search"]
    }

    wrap_result(id, {:ok, context})
  end

  # ----------------------------------------------------------------------------
  # MCP operations stubs
  # ----------------------------------------------------------------------------
  defp mcp_connection_create(%{"id" => id, "params" => %{"url" => url} = params}) do
    auth = Map.get(params, "auth", %{})

    case Lang.MCP.ConnectionManager.create_connection(url, auth) do
      {:ok, conn_id} ->
        wrap_result(id, {:ok, %{connection_id: conn_id, status: "connected"}})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  defp mcp_connection_destroy(%{"id" => id, "params" => %{"connection_id" => conn_id}}) do
    case Lang.MCP.ConnectionManager.destroy_connection(conn_id) do
      :ok ->
        wrap_result(id, {:ok, %{destroyed: true}})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  defp mcp_connection_status(%{"id" => id, "params" => %{"connection_id" => conn_id}}) do
    case Lang.MCP.ConnectionManager.get_status(conn_id) do
      {:ok, status} ->
        wrap_result(id, {:ok, status})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  # ----------------------------------------------------------------------------
  # RPC operations stubs
  # ----------------------------------------------------------------------------
  defp rpc_initialize(%{"id" => id, "params" => params}) do
    # Initialize RPC connection
    capabilities = %{
      methods: Lang.LSP.Registry.lookup_all() |> Map.keys(),
      version: "1.0.0",
      features: ["streaming", "batch", "async"]
    }

    wrap_result(id, {:ok, %{capabilities: capabilities, initialized: true}})
  end

  defp rpc_shutdown(%{"id" => id, "params" => _params}) do
    # Graceful shutdown
    Task.start(fn ->
      Process.sleep(100)
      # Cleanup tasks here
    end)

    wrap_result(id, {:ok, %{shutdown: true}})
  end

  defp rpc_ping(%{"id" => id, "params" => params}) do
    timestamp = Map.get(params, "timestamp", DateTime.utc_now())
    wrap_result(id, {:ok, %{status: "pong", timestamp: timestamp, latency_ms: 1}})
  end

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
