defmodule Lang.LSP.Dispatch do
  @moduledoc "Dispatches LSP JSON-RPC method maps to domain facades."

  @not_impl_methods ~w(
    lang.think.suggest_refactor
    lang.generate.from_diagram
    lang.generate.from_spec
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
    lang.agent.spawn
  )

  def process(%{"method" => method} = msg) do
    case method do
      # Dev model pipeline (guarded by :dev_routes)
      "lang.dev.models.list" -> dev_models_list(msg)
      "lang.dev.models.get" -> dev_models_get(msg)
      "lang.dev.models.history" -> dev_models_history(msg)
      "lang.dev.models.render" -> dev_models_render(msg)
      "lang.dev.models.ingest" -> dev_models_ingest(msg)
      "lang.dev.models.status" -> dev_models_status(msg)
      "lang.dev.models.drift" -> dev_models_drift(msg)
      "lang.dev.models.diff" -> dev_models_diff(msg)
      # Dev LSP tap/trace
      "lang.dev.lsp.tap_start" -> dev_lsp_tap_start(msg)
      "lang.dev.lsp.tap_stop" -> dev_lsp_tap_stop(msg)
      "lang.dev.lsp.trace" -> dev_lsp_trace(msg)
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
      "lang.think.review_code" -> think_review_code(msg)
      "lang.think.estimate_complexity" -> think(:estimate_complexity, msg)
      "lang.spatial.map" -> spatial_map(msg)
      "lang.spatial.traverse" -> spatial_traverse(msg)
      "lang.spatial.trace_path" -> spatial_trace_path(msg)
      "lang.spatial.find_related" -> spatial_find_related(msg)
      "lang.capabilities" -> capabilities(msg)
      "lang.generate.complete_partial" -> generate(:complete_partial, msg)
      # Marked as planned/not implemented
      "lang.generate.from_spec" -> not_implemented(msg)
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
      # New lightweight methods
      "lang.agent.self_reflect" -> agent_self_reflect(msg)
      "lang.prompt.optimize" -> prompt_optimize(msg)
      "lang.multi_modal.analyze" -> multi_modal_analyze(msg)
      "lang.agent.knowledge_share" -> agent_knowledge_share(msg)
      "lang.ml.rag_query" -> ml_rag_query(msg)
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
      "lang.agent.swarm_create" -> agent_swarm_create(msg)
      "lang_agent_swarm_create" -> agent_swarm_create(msg)
      "lang.agent.swarm_get" -> agent_swarm_get(msg)
      "lang_agent_swarm_get" -> agent_swarm_get(msg)
      "lang.agent.terminate" -> agent_terminate(msg)
      "lang.agent.get_status" -> agent_get_status(msg)
      "lang.agent.scan" -> agent_scan(msg)
      "lang.agent.verify_profile" -> agent_verify_profile(msg)
      "lang.agent.detect_rogue" -> agent_detect_rogue(msg)
      "lang.agent.quarantine" -> agent_quarantine(msg)
      "lang.agent.behavior_baseline" -> agent_behavior_baseline(msg)
      "lang_wake_qwen" -> wake_qwen(msg)
      "lang.agent.anomaly_score" -> agent_anomaly_score(msg)
      "lang.agent.trust_level" -> agent_trust_level(msg)
      "lang.agent.audit_trail" -> agent_audit_trail(msg)
      "lang.agent.track_usage" -> agent_track_usage(msg)
      "lang.agent.limit_resources" -> agent_limit_resources(msg)
      "lang.agent.monitor_performance" -> agent_monitor_performance(msg)
      "lang.agent.auto_attach" -> agent_auto_attach(msg)
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
      "lang.storage.connect" -> storage_connect(msg)
      "lang.storage.get_status" -> storage_get_status(msg)
      "lang.storage.create_scratch" -> storage_create_scratch(msg)
      "lang.storage.get_scratch" -> storage_get_scratch(msg)
      "lang.storage.update_scratch" -> storage_update_scratch(msg)
      "lang.storage.cleanup_scratch" -> storage_cleanup_scratch(msg)
      "lang.storage.get_project_context" -> storage_get_project_context(msg)
      "lang.storage.validate_auth" -> storage_validate_auth(msg)
      # Analysis operations
      "lang.analyze.document" -> analyze_document(msg)
      "lang.analyze.batch" -> analyze_batch(msg)
      "lang.analyze.stream" -> analyze_stream(msg)
      # ML operations
      "lang.ml.anomaly.stats" -> ml_anomaly_stats(msg)
      "lang.ml.usage.predict" -> ml_usage_predict(msg)
      "lang.ml.anomaly.train" -> ml_anomaly_train(msg)
      "lang.ml.code_quality_predict" -> ml_code_quality_predict(msg)
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
      # JSON-LD helpers
      "lang.jsonld.compact" -> jsonld_compact(msg)
      "lang.jsonld.expand" -> jsonld_expand(msg)
      # Onboarding/help
      "lang.onboard" -> onboard(msg)
      # RPC operations
      "rpc.initialize" -> rpc_initialize(msg)
      "rpc.shutdown" -> rpc_shutdown(msg)
      "rpc.capabilities" -> rpc_capabilities(msg)
      # Session/lease management
      "lang.session.heartbeat" -> session_heartbeat(msg)
      "rpc.ping" -> rpc_ping(msg)
      m when m in @not_impl_methods -> not_implemented(msg)
      _ -> nil
    end
  end

  def process(_), do: nil

  # ----------------------------------------------------------------------------
  # Session / Lease
  # ----------------------------------------------------------------------------
  defp session_heartbeat(%{"id" => id, "params" => params}) do
    # Stateless ack; the per-connection instance renews lease upon seeing this method
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    %{"jsonrpc" => "2.0", "id" => id, "result" => %{ok: true, at: now}}
  end

  # ----------------------------------------------------------------------------
  # New lightweight handlers (safe stubs)
  # ----------------------------------------------------------------------------
  defp agent_self_reflect(%{"id" => id, "params" => params}) do
    prev = Map.get(params, "previous_output")
    criteria = List.wrap(Map.get(params, "criteria", [])) |> Enum.map(&to_string/1)

    reflection =
      cond do
        is_binary(prev) and prev != "" ->
          "Reflected on output. Suggestions focus on clarity, correctness, and adherence to criteria."
        true ->
          "No previous output provided; nothing to reflect."
      end

    improvements =
      (if is_binary(prev) and String.length(prev) > 0, do: ["tighten wording", "add examples"], else: []) ++
        (if Enum.any?(criteria), do: ["address criteria: " <> Enum.join(criteria, ", ")], else: [])

    score = if improvements == [], do: 0.9, else: 0.6
    wrap_result(id, {:ok, %{reflection: reflection, improvements: improvements, score: score}})
  end

  defp prompt_optimize(%{"id" => id, "params" => params}) do
    original = to_string(Map.get(params, "original_prompt", ""))
    examples = List.wrap(Map.get(params, "examples", []))

    optimized =
      original
      |> String.trim()
      |> String.replace(~r/\s+/, " ")
      |> then(fn s -> if examples != [], do: s <> "\n\nFollow the patterns shown in examples.", else: s end)

    est = if String.length(optimized) < max(String.length(original), 1), do: 0.2, else: 0.05
    wrap_result(id, {:ok, %{optimized_prompt: optimized, estimated_improvement: est}})
  end

  defp multi_modal_analyze(%{"id" => id, "params" => params}) do
    text = to_string(Map.get(params, "text", ""))
    image_url = to_string(Map.get(params, "image_url", ""))
    query = to_string(Map.get(params, "query", ""))

    analysis = %{
      summary: "Combined text/image analysis stub",
      text_tokens: String.split(text) |> length(),
      image_seen?: image_url != "",
      query: query
    }
    wrap_result(id, {:ok, %{analysis: analysis, entities: []}})
  end

  defp agent_knowledge_share(%{"id" => id, "params" => params}) do
    from_id = to_string(Map.get(params, "from_agent_id", ""))
    to_ids = List.wrap(Map.get(params, "to_agent_ids", [])) |> Enum.map(&to_string/1)
    _knowledge = Map.get(params, "knowledge")

    # Stub: acknowledge share without broadcasting over PubSub
    acks = Enum.map(to_ids, fn tid -> %{agent_id: tid, status: "accepted"} end)
    wrap_result(id, {:ok, %{shared: to_ids != [], acknowledgments: acks}})
  end

  defp ml_rag_query(%{"id" => id, "params" => params}) do
    query = to_string(Map.get(params, "query", ""))
    _kb = to_string(Map.get(params, "knowledge_base_id", ""))
    top_k = Map.get(params, "top_k", 3)

    # Stub: no retrieval; just echo query and empty docs
    docs = []
    response = if query == "", do: "", else: "No matching docs; generating response based on query only."
    wrap_result(id, {:ok, %{retrieved_docs: Enum.take(docs, top_k), generated_response: response}})
  end

  # ----------------------------------------------------------------------------
  # Minimal FS handlers (stubs route to native NIFs when possible)
  # ----------------------------------------------------------------------------
  defp fs_scan(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    path = Lang.JSONLD.get(params, "path") || Lang.JSONLD.get(params, "root")
    opts = [max_depth: Lang.JSONLD.get(params, "max_depth", 10)]

    result =
      with :ok <- allow_by_rate_limit("fs.scan") do
        case Lang.Native.FSScanner.scan(path, opts) do
          {:ok, res} -> {:ok, res}
          {:error, reason} -> {:error, reason}
        end
      end

    wrap_result(id, result)
  end

  defp fs_search(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    path = Lang.JSONLD.get(params, "path") || Lang.JSONLD.get(params, "root")
    query = Lang.JSONLD.get(params, "query") || Lang.JSONLD.get(params, "pattern")
    opts = [max_results: Lang.JSONLD.get(params, "max_results", 100)]
    result =
      with :ok <- allow_by_rate_limit("fs.search") do
        Lang.Native.FSScanner.search(path, query, opts)
      end
    wrap_result(id, result)
  end

  defp fs_search_code(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    path = Lang.JSONLD.get(params, "path") || Lang.JSONLD.get(params, "root")
    lang = Lang.JSONLD.get(params, "language")
    pat = Lang.JSONLD.get(params, "pattern")

    opts = [
      max_results: Lang.JSONLD.get(params, "max_results", 100),
      max_depth: Lang.JSONLD.get(params, "max_depth", 15)
    ]

    result =
      with :ok <- allow_by_rate_limit("fs.search_code") do
        Lang.Native.FSScanner.search_code(path, lang, pat, opts)
      end
    wrap_result(id, result)
  end

  defp fs_preview(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    path = Lang.JSONLD.get(params, "path")
    max_lines = Lang.JSONLD.get(params, "max_lines", 200)

    result =
      case Lang.Native.FSScanner.preview(path, max_lines: max_lines) do
        {:ok, lines} when is_list(lines) -> {:ok, Enum.join(lines, "\n")}
        other -> other
      end

    wrap_result(id, result)
  end

  defp fs_watch(%{"id" => id}) do
    # Bounded watcher: periodically scans and broadcasts snapshots to PubSub.
    # Avoids indefinite processes per process management guidelines.
    wrap_result(id, {:error, -32602, "Missing required parameters: params"})
  end

  defp fs_watch(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)

    path =
      Lang.JSONLD.get(params, "path") ||
        Lang.JSONLD.get(params, "root")

    interval_ms = Lang.JSONLD.get(params, "interval_ms", 5_000)
    duration_ms = Lang.JSONLD.get(params, "duration_ms", 30_000)

    include_globs = List.wrap(Lang.JSONLD.get(params, "include_globs", []))
    exclude_globs = List.wrap(Lang.JSONLD.get(params, "exclude_globs", []))
    max_depth = Lang.JSONLD.get(params, "max_depth", 10)

    cond do
      is_nil(path) or path == "" ->
        wrap_result(id, {:error, -32602, "Missing required parameters: path"})

      true ->
        stream_id = "fsw_" <> Integer.to_string(:erlang.unique_integer([:positive]))
        topic = "lsp:fs_watch:" <> stream_id

        scans = max(div(duration_ms, max(interval_ms, 1)), 1)

        Task.Supervisor.start_child(Lang.LSP.TaskSupervisor, fn ->
          Enum.reduce_while(1..scans, nil, fn n, _acc ->
            opts = [
              max_depth: max_depth,
              include_globs: include_globs,
              exclude_globs: exclude_globs
            ]

            evt =
              case Lang.Native.FSScanner.scan(path, opts) do
                {:ok, result} -> {:fs_snapshot, stream_id, %{seq: n, result: result}}
                {:error, reason} -> {:fs_error, stream_id, %{seq: n, reason: reason}}
              end

            Phoenix.PubSub.broadcast(Lang.PubSub, topic, evt)

            if n < scans do
              Process.sleep(interval_ms)
              {:cont, nil}
            else
              Phoenix.PubSub.broadcast(Lang.PubSub, topic, {:fs_watch_complete, stream_id})
              {:halt, nil}
            end
          end)
        end)

        wrap_result(
          id,
          {:ok,
           %{
             stream_id: stream_id,
             topic: topic,
             interval_ms: interval_ms,
             duration_ms: duration_ms
           }}
        )
    end
  end

  defp wrap_result(id, {:ok, data}), do: %{"jsonrpc" => "2.0", "id" => id, "result" => data}

  defp wrap_result(id, {:error, reason}),
    do: %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}

  # ----------------------------------------------------------------------------
  # Rate limit helper (best-effort; defaults to allow)
  # ----------------------------------------------------------------------------
  defp allow_by_rate_limit(action) do
    try do
      case Lang.Security.RateLimiter.check(nil, action) do
        :ok -> :ok
        {:error, :rate_limited} -> {:error, {:rate_limited, action}}
        other -> other
      end
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  # ----------------------------------------------------------------------------
  # Storage handlers (Folder-backed)
  # ----------------------------------------------------------------------------
  defp storage_connect(%{"id" => id}) do
    if dirup_enabled?(),
      do: wrap_result(id, Lang.Storage.Folder.get_status()),
      else: wrap_result(id, {:error, :dirup_disabled})
  end

  defp storage_get_status(%{"id" => id}) do
    if dirup_enabled?(),
      do: wrap_result(id, Lang.Storage.Folder.get_status()),
      else: wrap_result(id, {:error, :dirup_disabled})
  end

  defp storage_create_scratch(%{"id" => id, "params" => raw}) do
    params = maybe_json_map(raw)

    if dirup_enabled?(),
      do: wrap_result(id, Lang.Storage.Folder.create_scratch(params)),
      else: wrap_result(id, {:error, :dirup_disabled})
  end

  defp storage_get_scratch(%{"id" => id, "params" => raw}) do
    params = maybe_json_map(raw)
    scratch_id = Lang.JSONLD.get(params, "id") || Lang.JSONLD.get(params, "scratch_id")

    if dirup_enabled?(),
      do:
        wrap_result(
          id,
          (scratch_id && Lang.Storage.Folder.get_scratch(scratch_id)) || {:error, :missing_id}
        ),
      else: wrap_result(id, {:error, :dirup_disabled})
  end

  defp storage_update_scratch(%{"id" => id, "params" => raw}) do
    params = maybe_json_map(raw)
    scratch_id = Lang.JSONLD.get(params, "id") || Lang.JSONLD.get(params, "scratch_id")
    attrs = Lang.JSONLD.get(params, "attrs") || Map.drop(params, ["id", "scratch_id"])

    if dirup_enabled?() do
      wrap_result(
        id,
        if scratch_id do
          Lang.Storage.Folder.update_scratch(scratch_id, attrs)
        else
          {:error, :missing_id}
        end
      )
    else
      wrap_result(id, {:error, :dirup_disabled})
    end
  end

  defp storage_cleanup_scratch(%{"id" => id, "params" => raw}) do
    params = maybe_json_map(raw)

    if dirup_enabled?(),
      do: wrap_result(id, Lang.Storage.Folder.cleanup_scratch(params)),
      else: wrap_result(id, {:error, :dirup_disabled})
  end

  defp storage_get_project_context(%{"id" => id, "params" => raw}) do
    params = maybe_json_map(raw)
    project_id = Lang.JSONLD.get(params, "project_id") || Lang.JSONLD.get(params, "project")

    if dirup_enabled?(),
      do:
        wrap_result(
          id,
          (project_id && Lang.Storage.Folder.get_project_context(project_id)) ||
            {:error, :missing_project_id}
        ),
      else: wrap_result(id, {:error, :dirup_disabled})
  end

  defp storage_validate_auth(%{"id" => id}) do
    if dirup_enabled?(),
      do: wrap_result(id, Lang.Storage.Folder.validate_auth()),
      else: wrap_result(id, {:error, :dirup_disabled})
  end

  # ----------------------------------------------------------------------------
  # Agent helpers
  # ----------------------------------------------------------------------------
  defp agent_auto_attach(%{"id" => id, "params" => params}) do
    label = Map.get(params || %{}, "label")
    cid_hint =
      "cid_" <>
        (:crypto.hash(:sha256, (label || "agent") <> "|" <> Integer.to_string(System.unique_integer([:positive])))
         |> Base.encode16(case: :lower)
         |> binary_part(0, 12))

    result = %{
      identifyNotification: %{"method" => "lang/tester/identify", "params" => %{"clientId" => cid_hint}},
      recommendedCalls: [
        "rpc.capabilities",
        "rpc.serverInfo",
        "rpc.health"
      ]
    }

    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  defp dirup_enabled? do
    val = System.get_env("DIRUP_ENABLED") || System.get_env("LANG_FOLDER_ENABLED") || "0"
    String.downcase(val) in ["1", "true", "yes", "on"]
  end

  # ----------------------------------------------------------------------------
  # Minimal Storage stubs
  # ----------------------------------------------------------------------------
  defp storage_create_session(%{"id" => id, "params" => %{"project_id" => project_id} = params}) do
    metadata = Map.get(params, "metadata", %{})
    wrap_result(id, Lang.Storage.Session.create(project_id, metadata))
  end

  defp storage_get_session(%{"id" => id, "params" => %{"session_id" => session_id}}) do
    wrap_result(id, Lang.Storage.Session.get(session_id))
  end

  defp storage_close_session(%{"id" => id, "params" => %{"session_id" => session_id}}) do
    :ok = Lang.Storage.Session.close(session_id)
    wrap_result(id, {:ok, %{closed: true, session_id: session_id}})
  end

  defp storage_sync_session(%{"id" => id, "params" => %{"session_id" => session_id}}) do
    case Lang.Storage.Session.sync(session_id) do
      {:ok, session} -> wrap_result(id, {:ok, %{synced: true, session: session}})
      other -> wrap_result(id, other)
    end
  end

  defp storage_update_user_context(%{
         "id" => id,
         "params" => %{"user_id" => user_id, "context" => context}
       }) do
    result =
      if dirup_enabled?() do
        Lang.Storage.Folder.update_user_context(user_id, context)
      else
        :ok = Lang.InMemory.Store.put(:user_contexts, user_id, context)
        {:ok, %{updated: true, user_id: user_id}}
      end

    wrap_result(id, result)
  end

  defp storage_get_user_context(%{"id" => id, "params" => %{"user_id" => user_id}}) do
    result =
      if dirup_enabled?() do
        Lang.Storage.Folder.get_user_context(user_id)
      else
        ctx = Lang.InMemory.Store.get(:user_contexts, user_id, %{})
        {:ok, %{user_id: user_id, context: ctx}}
      end

    wrap_result(id, result)
  end

  defp storage_store_patterns(%{"id" => id, "params" => %{"patterns" => patterns}}) do
    result =
      if dirup_enabled?() do
        Lang.Storage.Folder.store_patterns(patterns)
      else
        with {:ok, recs} <- Lang.Storage.PatternStore.store_many(patterns) do
          {:ok, %{stored: length(recs), pattern_ids: Enum.map(recs, & &1.id)}}
        end
      end

    wrap_result(id, result)
  end

  defp storage_get_patterns(%{"id" => id, "params" => %{"pattern_ids" => pattern_ids}}) do
    result =
      if dirup_enabled?() do
        Lang.Storage.Folder.get_patterns(pattern_ids)
      else
        with {:ok, recs} <- Lang.Storage.PatternStore.get_many(pattern_ids) do
          {:ok,
           %{
             patterns:
               Enum.map(recs, fn rec ->
                 %{id: rec.id, pattern: rec.content, confidence: rec.confidence}
               end)
           }}
        end
      end

    wrap_result(id, result)
  end

  defp storage_search_patterns(%{"id" => id, "params" => %{"query" => query}}) do
    all = Lang.InMemory.Store.list(:patterns)

    results =
      Enum.filter_map(
        all,
        fn {pid, pat} ->
          str = to_string(pat)
          String.contains?(String.downcase(str), String.downcase(query))
        end,
        fn {pid, pat} -> %{id: pid, pattern: pat, score: 1.0} end
      )

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

  defp analyze_stream(%{"id" => id, "params" => %{"content" => content} = params}) do
    stream_id = "analysis_#{:erlang.unique_integer([:positive])}"
    format = Map.get(params, "format", "text")

    callback = fn evt ->
      Phoenix.PubSub.broadcast(Lang.PubSub, "lsp:analysis:#{stream_id}", evt)
    end

    case Lang.TextIntelligence.AnalysisEngine.analyze_stream(content, format, callback) do
      {:ok, _sid} -> wrap_result(id, {:ok, %{stream_id: stream_id, status: "streaming"}})
      {:error, reason} -> wrap_result(id, {:error, reason})
    end
  end

  defp parser_parse(%{"id" => id, "params" => %{"content" => content} = params}) do
    fmt = Map.get(params, "format") || Lang.TextIntelligence.FormatDetector.detect(content)
    wrap_result(id, parse_by_format(fmt, content))
  end

  defp parser_parse_batch(%{"id" => id, "params" => %{"documents" => files}}) do
    parsed =
      Enum.map(files, fn
        %{"uri" => uri, "content" => content} ->
          fmt =
            Lang.TextIntelligence.FormatDetector.detect_from_uri(uri) ||
              Lang.TextIntelligence.FormatDetector.detect(content)

          {uri, parse_by_format(fmt, content)}

        _ ->
          {nil, {:error, :invalid_document}}
      end)

    wrap_result(id, {:ok, %{documents: parsed}})
  end

  defp parser_parse_stream(%{"id" => id, "params" => params}) do
    stream_id = "parser_#{:erlang.unique_integer([:positive])}"
    wrap_result(id, {:ok, %{stream_id: stream_id, status: "streaming"}})
  end

  defp parser_detect_format(%{"id" => id, "params" => params}) do
    content = Map.get(params, "content")
    uri = Map.get(params, "uri")

    format =
      cond do
        is_binary(content) -> Lang.TextIntelligence.FormatDetector.detect(content)
        is_binary(uri) -> Lang.TextIntelligence.FormatDetector.detect_from_uri(uri)
        true -> "unknown"
      end

    wrap_result(id, {:ok, %{format: format}})
  end

  # Shared parser helpers
  defp parse_by_format("json", content) do
    case Jason.decode(content) do
      {:ok, data} -> {:ok, %{format: "json", data: data}}
      {:error, reason} -> {:error, {:json_parse_error, reason}}
    end
  end

  defp parse_by_format("yaml", content) do
    try do
      {:ok, YamlElixir.read_from_string(content)}
    rescue
      e -> {:error, {:yaml_parse_error, e}}
    end
  end

  defp parse_by_format("markdown", content) do
    case Kyozo.Lang.UniversalParser.Formats.Markdown.parse_minimal(content) do
      {:ok, basic} -> {:ok, %{format: "markdown", structure: basic}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_by_format(fmt, content) when is_binary(fmt) do
    {:ok, %{format: fmt, content: content}}
  end

  defp graph_build(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)

    # Back-compat path: direct nodes/edges write
    nodes = Lang.JSONLD.get_list(params, "nodes")
    edges = Lang.JSONLD.get_list(params, "edges")

    result =
      cond do
        nodes != [] or edges != [] ->
          project_id = Lang.JSONLD.get(params, "project_id") || Lang.JSONLD.get(params, "project")
          graph = %{nodes: nodes, edges: edges, updated_at: DateTime.utc_now()}
          :ok = Lang.InMemory.Store.put(:graphs, project_id, graph)
          {:ok, %{project_id: project_id, nodes: length(nodes), edges: length(edges)}}

        docs = Lang.JSONLD.get_list(params, "documents") ->
          # Build knowledge graph from documents [{format, content}]
          opts = Lang.JSONLD.get(params, "options", %{})

          if truthy?(Lang.JSONLD.get(params, "stream")) do
            stream_id = "kg_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
            topic = "lsp:kg_build:" <> stream_id

            Task.Supervisor.start_child(Lang.LSP.TaskSupervisor, fn ->
              total = length(docs)
              emit_kg(stream_id, :start, 0, total, 0.0, %{message: "starting"})

              ld_acc =
                docs
                |> Enum.with_index(1)
                |> Enum.reduce([], fn {doc, idx}, acc ->
                  emit_kg(stream_id, :extract, idx, total, idx / max(total, 1), %{doc_index: idx})
                  case normalize_doc(doc) do
                    %{format: fmt, content: content} ->
                      case Kyozo.Lang.UniversalParser.LinkedDataExtractor.extract_from_content(content, fmt) do
                        {:ok, ld} -> [ld | acc]
                        {:error, reason} ->
                          emit_kg(stream_id, :error, idx, total, idx / max(total, 1), %{error: inspect(reason)})
                          acc
                      end
                  end
                end)
                |> Enum.reverse()

              case Kyozo.Lang.UniversalParser.KnowledgeGraph.build_from_linked_data(ld_acc, Map.to_list(opts)) do
                {:ok, graph} ->
                  emit_kg(stream_id, :build, total, total, 1.0, %{stats: graph[:stats] || %{}})
                  emit_kg(stream_id, :done, total, total, 1.0, %{graph: graph}, complete: true)
                {:error, reason} ->
                  emit_kg(stream_id, :error, total, total, 1.0, %{error: inspect(reason)}, complete: true)
              end
            end)

            {:ok, %{stream_id: stream_id, topic: topic}}
          else
            ld_list =
              docs
              |> Enum.map(&normalize_doc/1)
              |> Enum.map(fn
                %{format: fmt, content: content} ->
                  case Kyozo.Lang.UniversalParser.LinkedDataExtractor.extract_from_content(content, fmt) do
                    {:ok, ld} -> {:ok, ld}
                    {:error, reason} -> {:error, reason}
                  end
              end)
              |> collect_ok()

            case ld_list do
              {:ok, linked_data} ->
                case Kyozo.Lang.UniversalParser.KnowledgeGraph.build_from_linked_data(linked_data, Map.to_list(opts)) do
                  {:ok, graph} -> {:ok, graph}
                  other -> other
                end

              {:error, reason} -> {:error, reason}
            end
          end

        true ->
          {:error, -32602, "Missing required parameters: nodes/edges or documents"}
      end

    wrap_result(id, result)
  end

  defp normalize_doc(%{"format" => fmt, "content" => content}), do: %{format: normalize_fmt(fmt), content: to_string(content)}
  defp normalize_doc(%{format: fmt, content: content}), do: %{format: normalize_fmt(fmt), content: to_string(content)}
  defp normalize_doc(other) when is_binary(other), do: %{format: :markdown_ld, content: other}
  defp normalize_doc(_), do: %{format: :markdown_ld, content: ""}

  defp normalize_fmt(fmt) when is_atom(fmt), do: fmt
  defp normalize_fmt(fmt) when is_binary(fmt) do
    case String.downcase(fmt) do
      "jsonld" -> :jsonld
      "markdown_ld" -> :markdown_ld
      "markdown" -> :markdown_ld
      "json" -> :jsonld
      other -> String.to_atom(other)
    end
  end

  defp collect_ok(list) do
    {oks, errs} = Enum.split_with(list, &match?({:ok, _}, &1))
    if errs == [], do: {:ok, Enum.map(oks, fn {:ok, v} -> v end)}, else: hd(errs)
  end

  defp emit_kg(stream_id, phase, idx, total, progress, payload, opts \\ []) do
    params = %{
      stream_id: stream_id,
      phase: phase,
      index: idx,
      total: total,
      progress: progress,
      complete: Keyword.get(opts, :complete, false),
      payload: payload
    }

    _ = Ash.create(Lang.LSP.Events.GraphBuildEvent, params, action: :emit)
  end

  defp truthy?(val) do
    case val do
      true -> true
      1 -> true
      "1" -> true
      "true" -> true
      "on" -> true
      _ -> false
    end
  end

  defp graph_update(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    project_id = Lang.JSONLD.get(params, "project_id") || Lang.JSONLD.get(params, "project")
    add_nodes = Lang.JSONLD.get_list(params, "nodes")
    add_edges = Lang.JSONLD.get_list(params, "edges")
    current = Lang.InMemory.Store.get(:graphs, project_id, %{nodes: [], edges: []})
    nodes = Enum.uniq_by(current.nodes ++ add_nodes, fn n -> n["id"] || n[:id] end)

    edges =
      Enum.uniq_by(current.edges ++ add_edges, fn e ->
        {e["from"] || e[:from], e["to"] || e[:to]}
      end)

    :ok =
      Lang.InMemory.Store.put(:graphs, project_id, %{
        nodes: nodes,
        edges: edges,
        updated_at: DateTime.utc_now()
      })

    wrap_result(id, {:ok, %{project_id: project_id, nodes: length(nodes), edges: length(edges)}})
  end

  defp graph_traverse(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    project_id = Lang.JSONLD.get(params, "project_id") || Lang.JSONLD.get(params, "project")
    start = Lang.JSONLD.get(params, "start_node") || Lang.JSONLD.get(params, "start")
    depth = Lang.JSONLD.get(params, "depth", 1)
    graph = Lang.InMemory.Store.get(:graphs, project_id, %{nodes: [], edges: []})
    {nodes, edges} = bfs(graph, start, max(0, depth))
    wrap_result(id, {:ok, %{nodes: nodes, edges: edges, depth: depth}})
  end

  defp graph_query(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    project_id = Lang.JSONLD.get(params, "project_id") || Lang.JSONLD.get(params, "project")
    graph = Lang.InMemory.Store.get(:graphs, project_id, %{nodes: [], edges: []})
    q = Lang.JSONLD.get(params, "query", "") |> to_string() |> String.downcase()

    results =
      Enum.filter(graph.nodes, fn n ->
        s = String.downcase(to_string(n["label"] || n[:label] || n["id"] || n[:id] || ""))
        String.contains?(s, q)
      end)

    wrap_result(id, {:ok, %{results: results}})
  end

  defp graph_visualize(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    project_id = Lang.JSONLD.get(params, "project_id") || Lang.JSONLD.get(params, "project")
    graph = Lang.InMemory.Store.get(:graphs, project_id, %{nodes: [], edges: []})
    wrap_result(id, {:ok, Map.merge(graph, %{layout: "force-directed", format: "d3"})})
  end

  defp bfs(%{nodes: nodes, edges: edges}, start, depth) do
    node_ids = MapSet.new(Enum.map(nodes, fn n -> n["id"] || n[:id] end))
    start_id = start

    if not MapSet.member?(node_ids, start_id) do
      {[], []}
    else
      adj =
        Enum.reduce(edges, %{}, fn e, acc ->
          from = e["from"] || e[:from]
          to = e["to"] || e[:to]
          Map.update(acc, from, [to], fn lst -> [to | lst] end)
        end)

      {visited, traversed_edges} = bfs_visit([start_id], adj, MapSet.new(), [], depth)
      found_nodes = Enum.filter(nodes, fn n -> MapSet.member?(visited, n["id"] || n[:id]) end)
      {found_nodes, traversed_edges}
    end
  end

  defp bfs_visit(_queue, _adj, visited, edge_acc, 0), do: {visited, edge_acc}
  defp bfs_visit([], _adj, visited, edge_acc, _d), do: {visited, edge_acc}

  defp bfs_visit(queue, adj, visited, edge_acc, depth) do
    {current, rest} = List.pop_at(queue, 0)
    nexts = Map.get(adj, current, []) |> Enum.reject(&MapSet.member?(visited, &1))
    new_edges = Enum.map(nexts, fn n -> %{from: current, to: n} end)
    new_visited = MapSet.put(visited, current)
    bfs_visit(rest ++ nexts, adj, new_visited, edge_acc ++ new_edges, depth - 1)
  end

  # ----------------------------------------------------------------------------
  # Security operations stubs
  # ----------------------------------------------------------------------------
  defp security_validate(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    input = Lang.JSONLD.get(params, "input")
    rules = Lang.JSONLD.get(params, "rules", [])

    result =
      case Lang.Security.Validator.validate(input, rules) do
        :ok -> {:ok, %{valid: true}}
        {:error, violations} -> {:ok, %{valid: false, violations: violations}}
      end

    wrap_result(id, result)
  end

  defp security_sanitize(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    input = Lang.JSONLD.get(params, "input")
    type = Lang.JSONLD.get(params, "type") |> normalize_sanitize_type()
    sanitized = Lang.Security.Sanitizer.sanitize(input, type)
    wrap_result(id, {:ok, %{sanitized: sanitized}})
  end

  defp security_rate_limit(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    user_id = Lang.JSONLD.get(params, "user_id") || Lang.JSONLD.get(params, "user")
    action = Lang.JSONLD.get(params, "action")

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
  defp metrics_performance(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    period = Lang.JSONLD.get(params, "period", "24h")
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

  defp metrics_usage(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    user_id = Lang.JSONLD.get(params, "user_id") || Lang.JSONLD.get(params, "user")
    period = Lang.JSONLD.get(params, "period", "24h")

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
  defp orchestration_start(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    workflow = Lang.JSONLD.get(params, "workflow", %{})
    # Start orchestration workflow
    case Lang.Orchestration.Master.start_workflow(workflow, params) do
      {:ok, workflow_id} ->
        wrap_result(id, {:ok, %{workflow_id: workflow_id, status: "started"}})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  defp orchestration_status(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    workflow_id = Lang.JSONLD.get(params, "workflow_id") || Lang.JSONLD.get(params, "id")

    case Lang.Orchestration.Master.get_status(workflow_id) do
      {:ok, status} ->
        wrap_result(id, {:ok, status})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  defp orchestration_cancel(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    workflow_id = Lang.JSONLD.get(params, "workflow_id") || Lang.JSONLD.get(params, "id")

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
  defp workspace_create(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    name = Lang.JSONLD.get(params, "name") || Lang.JSONLD.get(params, "title")
    workspace_id = "workspace_#{:erlang.unique_integer([:positive])}"

    # Store workspace metadata
    workspace = %{
      id: workspace_id,
      name: name,
      root_path: Lang.JSONLD.get(params, "root_path") || Lang.JSONLD.get(params, "root"),
      created_at: DateTime.utc_now()
    }

    wrap_result(id, {:ok, workspace})
  end

  defp workspace_save(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    workspace_id = Lang.JSONLD.get(params, "workspace_id") || Lang.JSONLD.get(params, "workspace")
    # Save workspace state
    wrap_result(id, {:ok, %{saved: true, workspace_id: workspace_id}})
  end

  defp workspace_load(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    workspace_id = Lang.JSONLD.get(params, "workspace_id") || Lang.JSONLD.get(params, "workspace")
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

  defp workspace_context(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    workspace_id = Lang.JSONLD.get(params, "workspace_id") || Lang.JSONLD.get(params, "workspace")
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
  defp mcp_connection_create(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    url = Lang.JSONLD.get(params, "url") || Lang.JSONLD.get(params, "endpoint")
    auth =
      Lang.JSONLD.get(params, "auth", %{})
      |> Map.put_new("client_id", Lang.JSONLD.get(params, "client_id") || Lang.JSONLD.get(params, "clientId"))

    case Lang.MCP.ConnectionManager.create_connection(url, auth) do
      {:ok, conn_id} ->
        wrap_result(id, {:ok, %{connection_id: conn_id, status: "connected"}})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  defp mcp_connection_destroy(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    conn_id = Lang.JSONLD.get(params, "connection_id") || Lang.JSONLD.get(params, "id")

    case Lang.MCP.ConnectionManager.destroy_connection(conn_id) do
      :ok ->
        wrap_result(id, {:ok, %{destroyed: true}})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  defp mcp_connection_status(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    conn_id = Lang.JSONLD.get(params, "connection_id") || Lang.JSONLD.get(params, "id")

    case Lang.MCP.ConnectionManager.get_status(conn_id) do
      {:ok, status} ->
        wrap_result(id, {:ok, status})

      {:error, reason} ->
        wrap_result(id, {:error, reason})
    end
  end

  # ----------------------------------------------------------------------------
  # Agent Swarm operations
  # ----------------------------------------------------------------------------
  defp agent_swarm_create(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)

    goals = Lang.JSONLD.get(params, "goals", [])
    agent_count = Lang.JSONLD.get(params, "agent_count", 0)
    coord = Lang.JSONLD.get(params, "coordinator_id")

    cond do
      not is_list(goals) or goals == [] ->
        wrap_result(id, {:error, %{code: -32602, message: "goals must be a non-empty list"}})

      not is_integer(agent_count) or agent_count <= 0 or agent_count > 32 ->
        wrap_result(id, {:error, %{code: -32602, message: "agent_count must be 1..32"}})

      true ->
        swarm_id = "swarm_" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
        agent_ids =
          for i <- 1..agent_count do
            suffix = Integer.to_string(i)
            base = Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)
            "agent_" <> base <> "_" <> suffix
          end

        Lang.Events.track_event(%{
          event_type: "agent_swarm_created",
          metadata: %{
            swarm_id: swarm_id,
            coordinator_id: coord,
            goals: goals,
            agent_count: agent_count
          }
        })

        # Persist a Swarm record (best-effort Ash)
        _ =
          try do
            Ash.create(Lang.Agent.Swarm, %{
              swarm_id: swarm_id,
              goals: goals,
              agent_ids: agent_ids,
              coordinator_id: coord,
              status: :created
            })
          rescue
            _ -> :ok
          end

        # Best-effort background provisioning via Oban (if available)
        _ =
          case Code.ensure_loaded?(Oban) do
            true ->
              args = %{
                "swarm_id" => swarm_id,
                "agent_ids" => agent_ids,
                "goals" => goals,
                "coordinator_id" => coord
              }

              job = %{args: args}

              try do
                Oban.insert(Lang.Repo, Oban.Job.new(job, queue: :orchestration, worker: Lang.Workers.AgentSwarmWorker))
              rescue
                _ -> :ok
              end

            false ->
              :ok
          end

        wrap_result(id, {:ok, %{swarm_id: swarm_id, agent_ids: agent_ids, status: "created"}})
    end
  end

  defp agent_swarm_get(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    swarm_id = Lang.JSONLD.get(params, "swarm_id") || Lang.JSONLD.get(params, "id")

    cond do
      not is_binary(swarm_id) or swarm_id == "" ->
        wrap_result(id, {:error, %{code: -32602, message: "swarm_id is required"}})

      true ->
        try do
          query =
            Lang.Agent.Swarm
            |> Ash.Query.for_read(:by_swarm_id, %{swarm_id: swarm_id})
            |> Ash.Query.load(:agents)

          case Ash.read(query) do
            {:ok, [swarm]} ->
              agents = Enum.map(swarm.agents || [], fn a ->
                %{
                  id: a.id,
                  name: a.name,
                  state: a.state,
                  capabilities: a.capabilities,
                  session_id: a.session_id
                }
              end)

              result = %{
                swarm_id: swarm.swarm_id,
                status: swarm.status,
                goals: swarm.goals,
                agent_ids: swarm.agent_ids,
                coordinator_id: swarm.coordinator_id,
                agents: agents,
                metadata: swarm.metadata
              }

              wrap_result(id, {:ok, result})

            {:ok, []} ->
              wrap_result(id, {:error, %{code: -32004, message: "swarm not found"}})

            {:error, reason} ->
              wrap_result(id, {:error, %{code: -32000, message: "read error", data: inspect(reason)}})
          end
        rescue
          e -> wrap_result(id, {:error, %{code: -32000, message: Exception.message(e)}})
        end
    end
  end

  # ----------------------------------------------------------------------------
  # RPC operations stubs
  # ----------------------------------------------------------------------------
  defp rpc_initialize(%{"id" => id, "params" => _params}) do
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

  defp rpc_ping(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    timestamp = Lang.JSONLD.get(params, "timestamp", DateTime.utc_now())
    wrap_result(id, {:ok, %{status: "pong", timestamp: timestamp, latency_ms: 1}})
  end

  # ----------------------------------------------------------------------------
  # Onboarding helper
  # ----------------------------------------------------------------------------
  defp onboard(%{"id" => id, "params" => _params}) do
    # Provider health + tips to get started quickly from an LSP client
    provider_health = Lang.Providers.Provider.health_check_all()

    examples = %{
      lsp: [
        %{method: "lang.chat", params: %{action: "start_session", participants: ["user", "general"]}},
        %{method: "lang.chat", params: %{action: "send_message", message: "Explain the main modules"}},
        %{method: "lang.tokens.estimate", params: %{text: "def hello, do: :world"}},
        %{method: "lang.fs.scan", params: %{path: System.cwd!(), max_depth: 3}}
      ],
      tips: [
        "Use start_session to get a greeting and session_id",
        "Then send_message with session_id for replies",
        "Try hover/completion on an open buffer for inline help",
        "Call rpc.capabilities to discover supported methods"
      ]
    }

    missing = missing_api_keys()

    wrap_result(id,
      {:ok,
       %{
         message: "Welcome to LANG LSP — you’re ready to go.",
         provider_health: provider_health,
         missing_api_keys: missing,
         examples: examples
       }}
    )
  end

  defp missing_api_keys do
    cfg = Application.get_env(:lang, :ai_providers) || %{}

    [
      {:openai, :openai_api_key},
      {:anthropic, :anthropic_api_key},
      {:xai, :xai_api_key},
      {:gemini, :gemini_api_key}
    ]
    |> Enum.reduce([], fn {prov, key}, acc ->
      case cfg[key] do
        nil -> [{prov, to_string(key)} | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
  end

  # Return advertised capabilities and registered methods for onboarding/introspection
  defp rpc_capabilities(%{"id" => id, "params" => _params}) do
    caps = %{
      version: "1.0.0",
      features: ["streaming", "batch", "async"],
      methods: Lang.LSP.Registry.lookup_all() |> Map.keys()
    }

    wrap_result(id, {:ok, caps})
  end

  # ----------------------------------------------------------------------------
  # JSON-LD operations (local, no remote @context fetching)
  # ----------------------------------------------------------------------------
  defp jsonld_compact(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    doc = Lang.JSONLD.get(params, "doc") |> maybe_json_map()
    ctx = Lang.JSONLD.get(params, "@context") || Lang.JSONLD.get(params, "context") || %{}
    {compacted, used_ctx} = Lang.JSONLD.compact(doc, ctx)
    wrap_result(id, {:ok, %{"@context" => used_ctx, "document" => compacted}})
  end

  defp jsonld_expand(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    doc = Lang.JSONLD.get(params, "doc") |> maybe_json_map()
    ctx = Lang.JSONLD.get(params, "@context") || Lang.JSONLD.get(params, "context") || %{}
    {expanded, used_ctx} = Lang.JSONLD.expand(doc, ctx)
    wrap_result(id, {:ok, %{"@context" => used_ctx, "document" => expanded}})
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

  # Fast-path review_code: provide immediate lightweight feedback when possible
  # Falls back to generic think/3 enqueuing when realtime not requested or no inline code provided
  defp think_review_code(%{"id" => id, "params" => params} = msg) do
    code = Map.get(params || %{}, "code")

    cond do
      truthy?(Map.get(params || %{}, "stream")) and (is_binary(code) and code != "") ->
      stream_id = "review_" <> Integer.to_string(:erlang.unique_integer([:positive]))
        owner_cid = Map.get(params || %{}, "current_cid") || "anon"
        topic = "lsp:review:" <> to_string(owner_cid) <> ":" <> stream_id

        Task.Supervisor.start_child(Lang.LSP.TaskSupervisor, fn ->
          started_at = System.monotonic_time(:millisecond)
          emit_review_chunk(topic, :start, "Starting fast review for snippet (#{byte_size(code)} bytes)")

          {:ok, ast_or_err} =
            case :elixir.string_to_quoted(code) do
              {:ok, _ast} = ok -> emit_review_chunk(topic, :syntax, "Syntax OK"); ok
              {:error, {line, err, token}} ->
                emit_review_chunk(topic, :syntax_error, "Syntax error at line #{line}: #{Exception.format(:error, err, []) |> String.trim()} #{inspect(token)}")
                {:ok, :error}
            end

          checks = [
            {String.contains?(code, "IO.inspect"), "Warning: Found IO.inspect — remove before production"},
            {Regex.match?(~r/\bFile\./, code), "Use Lang.Native.FSScanner for filesystem ops"},
            {Regex.match?(~r/\bSystem\.(cmd)\b|:os\.cmd/, code), "Avoid shelling out; prefer safe adapters"},
            {Regex.match?(~r/String\.to_atom\(/, code), "Do not use String.to_atom on user input"},
            {Regex.match?(~r/\bTask\.async\(/, code) and not Regex.match?(~r/Task\.async_stream\(/, code), "Prefer Task.async_stream with back-pressure"}
          ]

          Enum.each(checks, fn
            {true, msg} -> emit_review_chunk(topic, :issue, msg)
            _ -> :ok
          end)

          dt = System.monotonic_time(:millisecond) - started_at
          :telemetry.execute([:lang, :lsp, :review_code, :fastpath], %{duration: dt}, %{mode: :stream, size: byte_size(code)})
            Phoenix.PubSub.broadcast(Lang.PubSub, topic, {:review_code, :completed, %{duration_ms: dt}})
        end)

        %{"jsonrpc" => "2.0", "id" => id, "result" => %{stream_id: stream_id, topic: topic, status: "streaming", mode: "fast", owner_cid: owner_cid}}

      realtime_request?(params) or (is_binary(code) and code != "") ->
        t0 = System.monotonic_time(:millisecond)
        review_text = quick_review_text(code)
        dt = System.monotonic_time(:millisecond) - t0
        _ = record_lsp_measurement("lang.think.review_code", params, %{review: String.slice(review_text, 0, 120)}, dt, nil)
        :telemetry.execute([:lang, :lsp, :review_code, :fastpath], %{duration: dt}, %{mode: :immediate, size: (is_binary(code) && byte_size(code)) || 0})
        %{"jsonrpc" => "2.0", "id" => id, "result" => %{review: review_text, mode: "fast"}}

      true ->
        think(:review_code, msg)
    end
  end

  defp quick_review_text(nil), do: "No code provided for review."
  defp quick_review_text(code) when is_binary(code) do
    base =
      case :elixir.string_to_quoted(code) do
        {:ok, _ast} -> []
        {:error, {line, err, token}} ->
          [
            "Syntax error at line #{line}: #{Exception.format(:error, err, []) |> String.trim()} #{inspect(token)}"
          ]
      end

    issues =
      []
      |> add_issue_if(String.contains?(code, "IO.inspect"),
        "Warning: Found IO.inspect — remove before production"
      )
      |> add_issue_if(Regex.match?(~r/\bFile\./, code),
        "Use Lang.Native.FSScanner for filesystem ops (project guideline)"
      )
      |> add_issue_if(Regex.match?(~r/\bSystem\.(cmd)\b|:os\.cmd/, code),
        "Avoid shelling out; prefer safe adapters"
      )
      |> add_issue_if(Regex.match?(~r/String\.to_atom\(/, code),
        "Do not use String.to_atom on user input"
      )
      |> add_issue_if(Regex.match?(~r/\bTask\.async\(/, code) and not Regex.match?(~r/Task\.async_stream\(/, code),
        "Prefer Task.async_stream with back-pressure"
      )
      |> add_issue_if(String.length(code) > 20_000,
        "Large snippet detected — consider streaming or summarizing input"
      )

    text =
      case base ++ issues do
        [] -> "Code parsed successfully. No obvious issues found."
        list -> Enum.join(list, "\n")
      end

    String.slice(text, 0, 8000)
  end

  defp add_issue_if(acc, true, msg), do: acc ++ [msg]
  defp add_issue_if(acc, false, _msg), do: acc

  defp record_lsp_measurement(method, request, response_preview, duration_ms, error) do
    # Best-effort Ash logging; must never crash the server/handler
    try do
      params = %{
        client_id: Map.get(request || %{}, "client_id") || "unknown",
        method: method,
        request: request || %{},
        response: response_preview || %{},
        duration_ms: duration_ms,
        error: error && to_string(error)
      }

      case Code.ensure_loaded?(Lang.LspDomain) and Code.ensure_loaded?(Lang.LspMeasurementEvent) do
        true ->
          _ = Ash.create(Lang.LspMeasurementEvent, params, action: :create)
          :ok
        false -> :ok
      end
    rescue
      _ -> :ok
    end
  end

  defp emit_review_chunk(topic, phase, text) do
    Phoenix.PubSub.broadcast(Lang.PubSub, topic, {:review_code, phase, %{text: text}})
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

  defp query(kind, %{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)

    req_attrs = %{
      kind: kind,
      query: Lang.JSONLD.get(params, "query", ""),
      context: Lang.JSONLD.get(params, "context", %{}),
      scope: Lang.JSONLD.get(params, "scope"),
      target_element:
        Lang.JSONLD.get(params, "target_element") || Lang.JSONLD.get(params, "targetElement"),
      change_description:
        Lang.JSONLD.get(params, "change_description") ||
          Lang.JSONLD.get(params, "changeDescription"),
      analysis_depth:
        parse_atom(
          Lang.JSONLD.get(params, "analysis_depth") || Lang.JSONLD.get(params, "analysisDepth")
        ),
      use_graph_reasoning: Lang.JSONLD.get(params, "use_graph_reasoning", true),
      provider_preference:
        Lang.JSONLD.get(params, "provider_preference") || Lang.JSONLD.get(params, "provider"),
      user_id: Lang.JSONLD.get(params, "user_id") || Lang.JSONLD.get(params, "user"),
      project_id: Lang.JSONLD.get(params, "project_id") || Lang.JSONLD.get(params, "project"),
      run_id: Lang.JSONLD.get(params, "run_id"),
      metadata: Lang.JSONLD.get(params, "metadata", %{})
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
        "lang.metrics.tokens",
        # Dev model pipeline
        "lang.dev.models.list",
        "lang.dev.models.get",
        "lang.dev.models.history",
        "lang.dev.models.render",
        "lang.dev.models.ingest",
        "lang.dev.models.status",
        "lang.dev.models.drift",
        "lang.dev.models.diff"
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

  # ----------------------------------------------------------------------------
  # Dev models (Lang.Dev.*) – guarded by :dev_routes
  # ----------------------------------------------------------------------------
  defp dev_enabled?(), do: Application.get_env(:lang, :dev_routes)

  defp dev_models_list(%{"id" => id}) do
    if dev_enabled?(), do: wrap_result(id, Lang.LSP.Dev.Models.List.handle(%{}, %{})), else: wrap_result(id, {:error, :dev_routes_disabled})
  end

  defp dev_models_get(%{"id" => id, "params" => raw}) do
    if dev_enabled?() do
      params = maybe_json_map(raw)
      wrap_result(id, Lang.LSP.Dev.Models.Get.handle(params, %{}))
    else
      wrap_result(id, {:error, :dev_routes_disabled})
    end
  end

  defp dev_models_history(%{"id" => id, "params" => raw}) do
    if dev_enabled?() do
      params = maybe_json_map(raw)
      wrap_result(id, Lang.LSP.Dev.Models.History.handle(params, %{}))
    else
      wrap_result(id, {:error, :dev_routes_disabled})
    end
  end

  defp dev_models_render(%{"id" => id, "params" => raw}) do
    if dev_enabled?() do
      params = maybe_json_map(raw)
      wrap_result(id, Lang.LSP.Dev.Models.Render.handle(params, %{}))
    else
      wrap_result(id, {:error, :dev_routes_disabled})
    end
  end

  defp dev_models_ingest(%{"id" => id, "params" => raw}) do
    if dev_enabled?() do
      params = maybe_json_map(raw)
      wrap_result(id, Lang.LSP.Dev.Models.Ingest.handle(params, %{}))
    else
      wrap_result(id, {:error, :dev_routes_disabled})
    end
  end

  defp dev_models_status(%{"id" => id, "params" => raw}) do
    if dev_enabled?() do
      params = maybe_json_map(raw)
      wrap_result(id, Lang.LSP.Dev.Models.Status.handle(params, %{}))
    else
      wrap_result(id, {:error, :dev_routes_disabled})
    end
  end

  defp dev_models_drift(%{"id" => id}) do
    if dev_enabled?(), do: wrap_result(id, Lang.LSP.Dev.Models.Drift.handle(%{}, %{})), else: wrap_result(id, {:error, :dev_routes_disabled})
  end

  defp dev_models_diff(%{"id" => id, "params" => raw}) do
    if dev_enabled?() do
      params = maybe_json_map(raw)
      wrap_result(id, Lang.LSP.Dev.Models.Diff.handle(params, %{}))
    else
      wrap_result(id, {:error, :dev_routes_disabled})
    end
  end

  defp dev_lsp_tap_start(%{"id" => id, "params" => raw}) do
    if dev_enabled?() do
      params = maybe_json_map(raw)
      wrap_result(id, Lang.LSP.Dev.Lsp.TapStart.handle(params, %{}))
    else
      wrap_result(id, {:error, :dev_routes_disabled})
    end
  end

  defp dev_lsp_tap_stop(%{"id" => id, "params" => raw}) do
    if dev_enabled?() do
      params = maybe_json_map(raw)
      wrap_result(id, Lang.LSP.Dev.Lsp.TapStop.handle(params, %{}))
    else
      wrap_result(id, {:error, :dev_routes_disabled})
    end
  end

  defp dev_lsp_trace(%{"id" => id, "params" => raw}) do
    if dev_enabled?() do
      params = maybe_json_map(raw)
      wrap_result(id, Lang.LSP.Dev.Lsp.Trace.handle(params, %{}))
    else
      wrap_result(id, {:error, :dev_routes_disabled})
    end
  end

  # ----------------------------------------------------------------------------
  # JSON helpers for tolerant parsing of stringified params
  # ----------------------------------------------------------------------------
  defp maybe_json_map(val) when is_binary(val) do
    case Jason.decode(val) do
      {:ok, %{} = map} -> map
      _ -> val
    end
  end

  defp maybe_json_map(%{} = v), do: v
  defp maybe_json_map(other), do: other

  defp maybe_json_list(val) when is_binary(val) do
    case Jason.decode(val) do
      {:ok, list} when is_list(list) -> list
      _ -> [val]
    end
  end

  defp maybe_json_list(list) when is_list(list), do: list
  defp maybe_json_list(nil), do: []
  defp maybe_json_list(other), do: [other]

  defp normalize_capabilities(val) when is_list(val) do
    Enum.flat_map(val, &normalize_capability/1)
  end

  defp normalize_capabilities(val) when is_binary(val) do
    val |> maybe_json_list() |> normalize_capabilities()
  end

  defp normalize_capabilities(_), do: []

  defp normalize_capability(v) when is_atom(v), do: [v]

  defp normalize_capability(v) when is_binary(v) do
    name = v |> String.trim() |> String.downcase()

    allowed = [
      :read_only,
      :analysis,
      :explain,
      :single_file_edit,
      :local_generation,
      :multi_file_coordination,
      :refactoring,
      :architecture_changes,
      :system_wide
    ]

    case Enum.find(allowed, fn a -> Atom.to_string(a) == name end) do
      nil -> []
      atom -> [atom]
    end
  end

  defp normalize_capability(_), do: []

  # Only atomize known keys to avoid creating atoms from user input (memory-safety)
  defp safe_atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      nk =
        case k do
          :type -> :type
          :required_capabilities -> :required_capabilities
          :content -> :content
          :analysis_type -> :analysis_type
          :goal -> :goal
          :strategy -> :strategy
          :reduce_fun -> :reduce_fun
          "type" -> :type
          "required_capabilities" -> :required_capabilities
          "content" -> :content
          "analysis_type" -> :analysis_type
          "goal" -> :goal
          "strategy" -> :strategy
          "reduce_fun" -> :reduce_fun
          other -> other
        end

      nv = if is_map(v), do: safe_atomize_keys(v), else: v
      {nk, nv}
    end)
  end

  defp safe_atomize_keys(other), do: other

  # === Agent namespace ===
  defp agent_spawn(%{"id" => id, "params" => params}) do
    caps =
      params
      |> maybe_json_map()
      |> Lang.JSONLD.get_list("capabilities")
      |> normalize_capabilities()

    constraints =
      params
      |> maybe_json_map()
      |> Lang.JSONLD.get("constraints", %{})

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
    task_ld = Map.get(params, "task", %{}) |> maybe_json_map()
    task = Lang.JSONLD.to_runtime_task(task_ld)

    case Lang.Agent.Lifecycle.delegate(agent_id, task) do
      {:ok, result} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => result}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp agent_coordinate(%{"id" => id, "params" => params}) do
    agent_ids = Map.get(params, "agent_ids", []) |> maybe_json_list()
    task_ld = Map.get(params, "task", %{}) |> maybe_json_map()
    task = Lang.JSONLD.to_runtime_task(task_ld)

    case Lang.Agent.Lifecycle.coordinate(agent_ids, task) do
      {:ok, result} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => result}

      {:error, reason} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: -32000, message: inspect(reason)}}
    end
  end

  defp wake_qwen(%{"id" => id, "params" => params}) do
    message = Map.get(params, "message", "Wake up, Qwen!")
    
    # Use our custom handler
    request = %Lang.LSP.Protocol.Types.Request{
      id: id,
      method: "lang_wake_qwen",
      params: params,
      client_id: Map.get(params, "client_id", "lsp_dispatch")
    }
    
    case Lang.LSP.Handlers.LangWakeQwen.handle_request(request, nil) do
      {:reply, response, _} ->
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => response.result
        }
        
      {:error, reason} ->
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => %{code: -32000, message: inspect(reason)}
        }
    end
  end

  defp agent_merge_results(%{"id" => id, "params" => params}) do
    results = Map.get(params, "results", []) |> maybe_json_list()

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

  defp tokens(kind, %{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)

    req_attrs = %{
      kind: kind,
      input: Lang.JSONLD.get(params, "input", %{}),
      model_type: Lang.JSONLD.get(params, "model_type") || Lang.JSONLD.get(params, "model"),
      target_ratio:
        parse_decimal(
          Lang.JSONLD.get(params, "target_ratio") || Lang.JSONLD.get(params, "targetRatio")
        ),
      user_id: Lang.JSONLD.get(params, "user_id") || Lang.JSONLD.get(params, "user"),
      project_id: Lang.JSONLD.get(params, "project_id") || Lang.JSONLD.get(params, "project"),
      run_id: Lang.JSONLD.get(params, "run_id"),
      metadata: Lang.JSONLD.get(params, "metadata", %{})
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

  defp normalize_sanitize_type(v) when is_atom(v), do: v

  defp normalize_sanitize_type(v) when is_binary(v) do
    case String.downcase(v) do
      "html" -> :html
      "url" -> :url
      "sql" -> :sql
      "json" -> :json
      _ -> :generic
    end
  end

  defp normalize_sanitize_type(_), do: :generic

  defp timeline(operation, %{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)

    with :ok <- realtime_request?(params) do
      case operation do
        :create ->
          content_id =
            Lang.JSONLD.get(params, "content_id") || Lang.JSONLD.get(params, "content") ||
              "default_#{:rand.uniform(10000)}"

          initial_state = Lang.JSONLD.get(params, "initial_state", %{})
          metadata = Lang.JSONLD.get(params, "metadata", %{})

          case Lang.Timeline.Core.create_timeline(content_id, initial_state, metadata) do
            {:ok, timeline_id} ->
              {:ok, id, %{timeline_id: timeline_id, content_id: content_id, created: true}}

            {:error, reason} ->
              {:error, id, -32603, "Timeline creation failed", %{reason: inspect(reason)}}
          end

        :add_state ->
          timeline_id =
            Lang.JSONLD.get(params, "timeline_id") || Lang.JSONLD.get(params, "timeline")

          state_data = Lang.JSONLD.get(params, "state_data", %{})
          metadata = Lang.JSONLD.get(params, "metadata", %{})

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
          timeline_id =
            Lang.JSONLD.get(params, "timeline_id") || Lang.JSONLD.get(params, "timeline")

          state_id = Lang.JSONLD.get(params, "state_id")

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
          timeline_id =
            Lang.JSONLD.get(params, "timeline_id") || Lang.JSONLD.get(params, "timeline")

          from_state_id = Lang.JSONLD.get(params, "from_state_id")
          branch_name = Lang.JSONLD.get(params, "branch_name") || Lang.JSONLD.get(params, "name")

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
          timeline_id =
            Lang.JSONLD.get(params, "timeline_id") || Lang.JSONLD.get(params, "timeline")

          from_state_id = Lang.JSONLD.get(params, "from_state_id")
          to_state_id = Lang.JSONLD.get(params, "to_state_id")

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
          timeline_id =
            Lang.JSONLD.get(params, "timeline_id") || Lang.JSONLD.get(params, "timeline")

          from_state_id = Lang.JSONLD.get(params, "from_state_id")
          to_state_id = Lang.JSONLD.get(params, "to_state_id")
          options = Lang.JSONLD.get(params, "options", %{})

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
          timeline_id =
            Lang.JSONLD.get(params, "timeline_id") || Lang.JSONLD.get(params, "timeline")

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

  # ----------------------------------------------------------------------------
  # ML operations handlers
  # ----------------------------------------------------------------------------
  defp ml_code_quality_predict(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    result = Lang.LSP.Handlers.MLCodeQuality.handle(%{"params" => params}, %{})
    wrap_ml_result(id, result)
  end

  defp ml_anomaly_stats(%{"id" => id, "params" => _params}) do
    result = Lang.LSP.ML.handle("lang.ml.anomaly.stats", %{}, %{})
    wrap_ml_result(id, result)
  end

  defp ml_usage_predict(%{"id" => id, "params" => raw_params}) do
    params = maybe_json_map(raw_params)
    user_id = Lang.JSONLD.get(params, "user_id")
    time_window = Lang.JSONLD.get(params, "time_window", "hour")

    result = Lang.LSP.ML.handle("lang.ml.usage.predict", %{"user_id" => user_id, "time_window" => time_window}, %{})
    wrap_ml_result(id, result)
  end

  defp ml_anomaly_train(%{"id" => id, "params" => _params}) do
    result = Lang.LSP.ML.handle("lang.ml.anomaly.train", %{}, %{})
    wrap_ml_result(id, result)
  end

  defp wrap_ml_result(id, {:ok, data}), do: %{"jsonrpc" => "2.0", "id" => id, "result" => data}
  defp wrap_ml_result(id, {:error, code, message, data, _session}),
    do: %{"jsonrpc" => "2.0", "id" => id, "error" => %{code: code, message: message, data: data}}
end
