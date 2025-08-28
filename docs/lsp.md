# LANG LSP Methods (Generated)

| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|---------------------|
| `lang.lang.agent.anomaly_score` | ❌ | High | Calculate deviation from expected behavior | `lib/lang/agent/behavioral.ex` |
| `lang.lang.agent.audit_trail` | ❌ | High | Full audit log of agent actions | `lib/lang/agent/audit.ex` |
| `lang.lang.agent.behavior_baseline` | ❌ | High | Establish normal behavior patterns | `lib/lang/agent/behavioral.ex` |
| `lang.lang.agent.coordinate` | ❌ | High | Coordinate multiple agents | `lib/lang/agent/coordinator.ex` |
| `lang.lang.agent.delegate` | ❌ | Critical | Delegate task to agent | `lib/lang/agent/coordinator.ex` |
| `lang.lang.agent.detect_rogue` | ❌ | Critical | Identify rogue/compromised agents | `lib/lang/agent/security.ex` |
| `lang.lang.agent.get_status` | ❌ | Medium | Check agent status | `lib/lang/agent/monitor.ex` |
| `lang.lang.agent.limit_resources` | ❌ | High | Set resource limits for agent | `lib/lang/agent/resources.ex` |
| `lang.lang.agent.merge_results` | ❌ | High | Merge findings from multiple agents | `lib/lang/agent/merger.ex` |
| `lang.lang.agent.monitor_performance` | ❌ | Medium | Real-time performance monitoring | `lib/lang/agent/monitor.ex` |
| `lang.lang.agent.quarantine` | ❌ | Critical | Isolate suspicious agent | `lib/lang/agent/security.ex` |
| `lang.lang.agent.scan` | ❌ | Critical | Scan another agent's behavior and patterns | `lib/lang/agent/security.ex` |
| `lang.lang.agent.spawn` | ❌ | Critical | Create agent with specific capabilities | `lib/lang/agent/lifecycle.ex` |
| `lang.lang.agent.terminate` | ❌ | Medium | Clean agent shutdown | `lib/lang/agent/lifecycle.ex` |
| `lang.lang.agent.track_usage` | ❌ | High | Track token/resource usage per agent | `lib/lang/agent/resources.ex` |
| `lang.lang.agent.trust_level` | ❌ | High | Assign trust score to agent | `lib/lang/agent/trust.ex` |
| `lang.lang.agent.verify_profile` | ❌ | Critical | Check agent against expected behavior profile | `lib/lang/agent/security.ex` |
| `lang.lang.analyze.batch` | 🚧 | High | Analyze multiple documents | `lib/lang/text_intelligence/analysis_engine.ex` |
| `lang.lang.analyze.document` | 🚧 | Critical | Analyze single document | `lib/lang/text_intelligence/analysis_engine.ex` |
| `lang.lang.analyze.stream` | ❌ | High | Streaming analysis | `_Not implemented_` |
| `lang.lang.fs.preview` | ✅ | Critical | File content preview via Rust NIF | `lib/lang/rpc/router.ex` |
| `lang.lang.fs.scan` | ✅ | Critical | Directory tree scanning via Rust NIF | `lib/lang/rpc/router.ex` |
| `lang.lang.fs.search` | ✅ | Critical | Regex text search via Rust NIF | `lib/lang/rpc/router.ex` |
| `lang.lang.fs.search_code` | ✅ | Critical | Tree-sitter semantic search via Rust NIF | `lib/lang/rpc/router.ex` |
| `lang.lang.fs.watch` | 🚧 | High | File system watching | `Lang.Native.FSWatcher` |
| `lang.lang.generate.agent.devops` | ❌ | High | Generate only in infrastructure/ | `lib/lang/generate/agent_bounded.ex` |
| `lang.lang.generate.agent.documentation` | ❌ | High | Generate only in docs/, *.md | `lib/lang/generate/agent_bounded.ex` |
| `lang.lang.generate.agent.implementation` | 🚧 | Critical | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.agent.testing` | 🚧 | Critical | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.api_gateway` | ❌ | High | Generate API gateway configs | `lib/lang/generate/services.ex` |
| `lang.lang.generate.ci_pipeline` | ❌ | High | Generate CI/CD pipelines | `lib/lang/generate/infrastructure.ex` |
| `lang.lang.generate.cognitive.architecture` | ❌ | Medium | Track 4: System-wide changes | `lib/lang/generate/cognitive.ex` |
| `lang.lang.generate.cognitive.feature` | 🚧 | Critical | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.cognitive.integration` | ❌ | High | Track 3: Cross-agent coordination | `lib/lang/generate/cognitive.ex` |
| `lang.lang.generate.cognitive.simple` | 🚧 | Critical | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.complete_partial` | 🚧 | Critical | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.compose` | ❌ | High | Generate docker-compose configs | `lib/lang/generate/infrastructure.ex` |
| `lang.lang.generate.dockerfile` | 🚧 | Critical | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.from_diagram` | ❌ | High | Architecture diagram → boilerplate | `lib/lang/generate/code.ex` |
| `lang.lang.generate.from_patterns` | 🚧 | Critical | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.from_spec` | 🚧 | Critical | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.from_tests` | 🚧 | Critical | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.gitops` | ❌ | Medium | Generate GitOps configurations | `lib/lang/generate/infrastructure.ex` |
| `lang.lang.generate.kubernetes` | ❌ | High | Generate K8s manifests | `lib/lang/generate/infrastructure.ex` |
| `lang.lang.generate.learn_patterns` | ❌ | High | Extract and learn from success | `lib/lang/generate/patterns.ex` |
| `lang.lang.generate.load_balancer` | ❌ | Medium | Generate load balancer configs | `lib/lang/generate/services.ex` |
| `lang.lang.generate.maintain_style` | ❌ | High | Match directory-specific style | `lib/lang/generate/patterns.ex` |
| `lang.lang.generate.migrate` | 🚧 | High | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.monitoring` | ❌ | High | Generate observability stack | `lib/lang/generate/services.ex` |
| `lang.lang.generate.optimize` | 🚧 | High | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.parallelize` | 🚧 | Medium | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.respect_boundaries` | 🚧 | Critical | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.generate.service_mesh` | ❌ | High | Generate service mesh configs | `lib/lang/generate/services.ex` |
| `lang.lang.generate.terraform` | ❌ | High | Generate infrastructure as code | `lib/lang/generate/infrastructure.ex` |
| `lang.lang.generate.variations` | 🚧 | High | Queued via Ash/Oban; working stub | `lib/lang/generate/workers/request_worker.ex` |
| `lang.lang.graph.build` | 🚧 | High | Build knowledge graph from text | `lib/kyozo/lang/universal_parser/knowledge_graph.ex` |
| `lang.lang.graph.query` | 🚧 | High | Advanced graph reasoning and queries | `lib/lang/graph_reasoner.ex` |
| `lang.lang.graph.traverse` | 🚧 | Medium | Graph traversal algorithms | `lib/lang/graph_reasoner.ex` |
| `lang.lang.graph.update` | ❌ | Medium | Update graph nodes/edges | `_Not implemented_` |
| `lang.lang.graph.visualize` | ❌ | Low | Visualize graph | `_Not implemented_` |
| `lang.lang.metrics.agent_efficiency` | ❌ | High | Agent resource usage | `lib/lang/metrics/agent_efficiency.ex` |
| `lang.lang.metrics.performance` | 🚧 | High | System performance metrics | `lib/lang/telemetry/metrics.ex` |
| `lang.lang.metrics.tokens` | ✅ | Critical | Token consumption tracking | `lib/lang/rpc/router.ex` |
| `lang.lang.metrics.usage` | 🚧 | High | API usage statistics | `lib/lang/accounts/api_usage_logger.ex` |
| `lang.lang.orchestration.cancel` | ❌ | Medium | Cancel running jobs | `_Not implemented_` |
| `lang.lang.orchestration.start` | ✅ | Critical | Launch distributed analysis | `lib/lang/orchestration/master.ex` |
| `lang.lang.orchestration.status` | ✅ | High | Monitor progress | `lib/lang/orchestration/master.ex` |
| `lang.lang.parser.detect_format` | ✅ | Critical | Auto-detect text format | `lib/kyozo/lang/universal_parser.ex` |
| `lang.lang.parser.parse` | ✅ | Critical | Universal text parsing | `lib/kyozo/lang/universal_parser.ex` |
| `lang.lang.parser.parse_batch` | ✅ | High | Batch document parsing | `lib/kyozo/lang/universal_parser.ex` |
| `lang.lang.parser.parse_stream` | ✅ | High | Streaming parser | `lib/kyozo/lang/universal_parser.ex` |
| `lang.lang.query.dependency` | ✅ | High | "What depends on this?" | `lib/lang/query/dependency.ex` |
| `lang.lang.query.impact` | ✅ | Critical | "What breaks if I change X?" | `lib/lang/query/impact.ex` |
| `lang.lang.query.natural` | ✅ | Critical | Natural language queries | `lib/lang/query/natural.ex` |
| `lang.lang.query.ownership` | ✅ | Medium | "Who owns this code?" | `lib/lang/query/ownership.ex` |
| `lang.lang.security.rate_limit` | ❌ | High | Rate limiting | `lib/lang/security/rate_limiter.ex` |
| `lang.lang.security.sanitize` | 🚧 | Critical | Input sanitization | `lib/lang/security/input_validator.ex` |
| `lang.lang.security.validate` | 🚧 | Critical | Request validation | `lib/lang/security/input_validator.ex` |
| `lang.lang.spatial.find_related` | ✅ | High | Relation-based similarity implemented | `lib/lang/spatial/mapper.ex` |
| `lang.lang.spatial.map` | 🚧 | Critical | Ash resource + Oban worker implemented | `lib/lang/spatial/map.ex` |
| `lang.lang.spatial.trace_path` | ✅ | High | Shortest path algorithm implemented | `lib/lang/spatial/mapper.ex` |
| `lang.lang.spatial.traverse` | ✅ | Critical | Full BFS implementation with depth control | `lib/lang/spatial/mapper.ex` |
| `lang.lang.spatial.waypoint_jump` | 🚧 | High | Ash resource implemented | `lib/lang/spatial/waypoint.ex` |
| `lang.lang.spatial.waypoint_set` | 🚧 | High | Ash resource implemented | `lib/lang/spatial/waypoint.ex` |
| `lang.lang.storage.cleanup_scratch` | ❌ | Medium | TTL-based scratch cleanup | `lib/lang/storage/scratch.ex` |
| `lang.lang.storage.close_session` | ❌ | Medium | Clean up session workspace | `lib/lang/storage/session.ex` |
| `lang.lang.storage.connect` | 🚧 | Critical | Basic Kyozo HTTP client implemented | `lib/lang/storage/kyozo.ex` |
| `lang.lang.storage.create_scratch` | ❌ | High | Create temporary scratch pipeline | `lib/lang/storage/scratch.ex` |
| `lang.lang.storage.create_session` | ❌ | Critical | Create new session workspace | `lib/lang/storage/session.ex` |
| `lang.lang.storage.get_patterns` | ❌ | Critical | Retrieve agent patterns from Kyozo | `lib/lang/storage/patterns.ex` |
| `lang.lang.storage.get_project_context` | ❌ | High | Load project-specific context | `lib/lang/storage/context.ex` |
| `lang.lang.storage.get_scratch` | ❌ | High | Retrieve scratch pipeline data | `lib/lang/storage/scratch.ex` |
| `lang.lang.storage.get_session` | ❌ | High | Retrieve session workspace | `lib/lang/storage/session.ex` |
| `lang.lang.storage.get_status` | 🚧 | High | Basic object operations available | `lib/lang/storage/kyozo.ex` |
| `lang.lang.storage.get_user_context` | ❌ | Critical | Load user preferences and history | `lib/lang/storage/context.ex` |
| `lang.lang.storage.search_patterns` | ❌ | High | Semantic search across stored patterns | `lib/lang/storage/patterns.ex` |
| `lang.lang.storage.store_patterns` | ❌ | Critical | Persist learned patterns to Kyozo | `lib/lang/storage/patterns.ex` |
| `lang.lang.storage.sync_session` | ❌ | Critical | Sync active session with Kyozo | `lib/lang/storage/session.ex` |
| `lang.lang.storage.update_confidence` | ❌ | High | Update pattern confidence scores | `lib/lang/storage/patterns.ex` |
| `lang.lang.storage.update_scratch` | ❌ | High | Update scratch transformation stage | `lib/lang/storage/scratch.ex` |
| `lang.lang.storage.update_user_context` | ❌ | High | Update user context in Kyozo | `lib/lang/storage/context.ex` |
| `lang.lang.storage.validate_auth` | 🚧 | Critical | Bearer token auth implemented | `lib/lang/storage/kyozo.ex` |
| `lang.lang.think.diagnose` | ✅ | Critical | AI-powered error analysis from stacktraces | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.estimate_complexity` | ✅ | Medium | AI-powered complexity analysis | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.explain_how` | ✅ | Critical | AI-powered with multi-provider support | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.explain_intent` | ✅ | Critical | AI-powered with multi-provider support | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.explain_why` | ✅ | Critical | AI-powered with multi-provider support | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.find_semantic` | ✅ | Critical | AI-powered semantic code search | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.find_similar` | ✅ | High | AI-powered similarity matching | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.generate_tests` | ✅ | High | AI-powered comprehensive test generation | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.predict_bugs` | ✅ | Critical | AI-powered bug prediction with confidence scoring | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.predict_performance` | ✅ | High | AI-powered performance analysis | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.review_code` | ✅ | High | AI-powered code review with quality scoring | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.security_scan` | ✅ | Critical | AI-powered security vulnerability scanning | `lib/lang/think/ai_engine.ex` |
| `lang.lang.think.trace_flow` | ✅ | Critical | AI-powered execution flow tracing | `lib/lang/think/ai_engine.ex` |
| `lang.lang.timeline.add_state` | ✅ | High | Add new state to timeline + LSP integration | `lib/lang/timeline/core.ex` |
| `lang.lang.timeline.analyze` | ✅ | Medium | Timeline analytics and insights + LSP integration | `lib/lang/timeline/core.ex` |
| `lang.lang.timeline.blame_semantic` | ❌ | High | Who introduced this concept (not line) | `lib/lang/timeline/semantic_blame.ex` |
| `lang.lang.timeline.branch` | ✅ | Medium | Create branches in timeline + LSP integration | `lib/lang/timeline/core.ex` |
| `lang.lang.timeline.create` | ✅ | High | Create timeline for content evolution + LSP integration | `lib/lang/timeline/core.ex` |
| `lang.lang.timeline.diff` | ✅ | High | Calculate diffs between states + LSP integration | `lib/lang/timeline/core.ex` |
| `lang.lang.timeline.evolution` | ❌ | High | How code evolved over time | `lib/lang/timeline/evolution.ex` |
| `lang.lang.timeline.find_decisions` | ❌ | Medium | Key architectural decision points | `lib/lang/timeline/decisions.ex` |
| `lang.lang.timeline.navigate` | ✅ | High | Navigate to specific timeline state + LSP integration | `lib/lang/timeline/core.ex` |
| `lang.lang.timeline.predict_changes` | ❌ | High | Predict likely future changes | `lib/lang/timeline/predictor.ex` |
| `lang.lang.timeline.regression_risk` | ❌ | High | What might break if changed | `lib/lang/timeline/risk.ex` |
| `lang.lang.timeline.replay` | ✅ | High | Replay timeline changes + LSP integration | `lib/lang/timeline/core.ex` |
| `lang.lang.tokens.cache_strategy` | ✅ | High | Optimize caching for tokens | `lib/lang/tokens/cache.ex` |
| `lang.lang.tokens.compress` | ✅ | Critical | Compress context intelligently | `lib/lang/tokens/compressor.ex` |
| `lang.lang.tokens.estimate` | ✅ | Critical | Estimate operation token cost | `lib/lang/tokens/estimator.ex` |
| `lang.lang.tokens.filter` | ✅ | Critical | Filter by relevance | `lib/lang/tokens/filter.ex` |
| `lang.lang.tokens.stream` | ✅ | Critical | Stream only deltas | `lib/lang/tokens/streamer.ex` |
| `lang.lang.workspace.context` | 🚧 | High | Get workspace context | `lib/lang/workspace/store.ex` |
| `lang.lang.workspace.create` | ✅ | Critical | Create analysis workspace | `lib/lang/workspace/workspace.ex` |
| `lang.lang.workspace.load` | ✅ | Critical | Load existing workspace | `lib/lang/workspace/workspace.ex` |
| `lang.lang.workspace.save` | ✅ | High | Save workspace state | `lib/lang/workspace/store.ex` |
| `lang.mcp.connection.create` | ✅ | High | Create MCP connection | `lib/lang/rpc/router.ex` |
| `lang.mcp.connection.destroy` | ✅ | Medium | Destroy connection | `lib/lang/rpc/router.ex` |
| `lang.mcp.connection.status` | ✅ | Medium | Check connection status | `lib/lang/rpc/router.ex` |
| `lang.rpc.initialize` | ✅ | Critical | Initialize LANG capabilities | `lib/lang/rpc/router.ex` |
| `lang.rpc.ping` | ✅ | High | Health check | `lib/lang/rpc/router.ex` |
| `lang.rpc.shutdown` | ✅ | Critical | Clean shutdown | `lib/lang/rpc/router.ex` |
| `lang.textDocument/completion` | 🚧 | Medium | Code completion | `lib/lang/lsp/server.ex` |
| `lang.textDocument/definition` | ❌ | Low | Go to definition | `_Not implemented_` |
| `lang.textDocument/didChange` | 🚧 | Medium | Document changed | `lib/lang/lsp/server.ex` |
| `lang.textDocument/didClose` | 🚧 | Low | Document closed | `lib/lang/lsp/server.ex` |
| `lang.textDocument/didOpen` | 🚧 | Medium | Document opened | `lib/lang/lsp/server.ex` |
| `lang.textDocument/documentSymbol` | ❌ | Low | Document outline | `_Not implemented_` |
| `lang.textDocument/formatting` | ❌ | Low | Format document | `_Not implemented_` |
| `lang.textDocument/hover` | 🚧 | Medium | Hover info | `lib/lang/lsp/server.ex` |
| `lang.textDocument/references` | ❌ | Low | Find references | `_Not implemented_` |
| `lang.workspace/executeCommand` | ❌ | Low | Execute commands | `_Not implemented_` |
| `lang.workspace/symbol` | ❌ | Low | Workspace symbol search | `_Not implemented_` |
