# LANG LSP Methods Reference - AI-First Architecture
## Current Implementation Status (Mapped to Modules)

- Implemented (server-side dispatch in `lib/lang/lsp/dispatch.ex`):
  - `lang.think.explain_intent` → `Lang.Think.Request.create_enqueued/1` (Ash Resource)
  - `lang.think.find_semantic` → `Lang.Think.Request.create_enqueued/1`
  - `lang.generate.complete_partial` → `Lang.Generate.Request.create_enqueued/1`
  - `lang.spatial.map` → `Lang.Spatial.ensure_map/2` (Oban worker)
  - `lang.spatial.traverse` → `Lang.Spatial.Mapper.traverse/2`
  - `lang.spatial.trace_path` → `Lang.Spatial.Mapper.trace_path/3`
  - `lang.spatial.find_related` → `Lang.Spatial.Mapper.find_related/3`
  - `lang.capabilities` → implemented/planned list

- Planned (stubs return JSON-RPC -32601 Not Implemented):
  - All remaining methods listed below under Think, Generate, Spatial, Agent, Timeline

## REST + JSON:API Surfaces

- Normalized Spatial Map (filters, pagination, counts):
  - `GET /api/v2/spatial/map/:project_id` → `LangWeb.Api.V2.SpatialController.map_summary/2`
  - Filters: `languages`, `types`, `kinds`, `section`, `counts_only`, plus field filters
  - Pagination: `page`, `page_size`

- Spatial traversal helpers:
  - `GET /api/v2/spatial/traverse/:project_id` → `LangWeb.Api.V2.SpatialController.traverse/2`
  - `GET /api/v2/spatial/trace_path/:project_id` → `LangWeb.Api.V2.SpatialController.trace_path/2`
  - `GET /api/v2/spatial/find_related/:project_id` → `LangWeb.Api.V2.SpatialController.find_related/2`

- AshJsonApi (resource-level):
  - Maps (read-only): `/api/v2/spatial/maps`
  - Waypoints CRUD: `/api/v2/spatial/waypoints`
  - Paths CRUD: `/api/v2/spatial/paths`

## Implementation Notes

- All data operations are implemented at the resource level (Ash) with `create_enqueued` actions enqueueing Oban jobs for long-running work.
- Filesystem traversal and code parsing are implemented with native Rust NIFs under `Lang.Native.FSScanner`.
- LSP server delegates to `Lang.LSP.Dispatch` to minimize duplication in `Lang.LSP.Server`.


→ **See also**: [`ai-context.md`](./lsp/ai-context.md) | [`acg-protocol.md`](./lsp/acg-protocol.md) | [`implementation-reference.md`](./lsp/implementation-reference.md) | [`ai-first-domains.md`](./lsp/ai-first-domains.md)

## 🧠 Core AI Intelligence (`lang.think.*`) → [`ai-first-domains.md`](./lsp/ai-first-domains.md#-langthink---cognitive-intelligence-domain)
*The cognitive layer where AI-backed intelligence lives*

| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.think.explain_intent` | ❌ | Critical | What is this code trying to accomplish? | `lib/lang/think/explainer.ex` |
| `lang.think.explain_why` | ❌ | Critical | Why does this code exist? Business context | `lib/lang/think/explainer.ex` |
| `lang.think.explain_how` | ❌ | Critical | Step-by-step execution explanation | `lib/lang/think/explainer.ex` |
| `lang.think.diagnose` | ❌ | Critical | Stack trace → Plain English diagnosis | `lib/lang/think/diagnostics.ex` |
| `lang.think.predict_bugs` | ❌ | Critical | Predict runtime failures from patterns | `lib/lang/think/predictor.ex` |
| `lang.think.predict_performance` | ❌ | High | Identify performance bottlenecks | `lib/lang/think/predictor.ex` |
| `lang.think.security_scan` | ❌ | Critical | AI-powered vulnerability detection | `lib/lang/think/security.ex` |
| `lang.think.find_semantic` | ❌ | Critical | Search by meaning, not syntax | `lib/lang/think/search.ex` |
| `lang.think.find_similar` | ❌ | High | Find similar patterns across codebase | `lib/lang/think/search.ex` |
| `lang.think.trace_flow` | ❌ | Critical | Trace data/control flow across files | `lib/lang/think/tracer.ex` |
| `lang.think.suggest_refactor` | ❌ | High | AI-driven refactoring proposals | `lib/lang/think/refactor.ex` |
| `lang.think.generate_tests` | ❌ | High | Smart test generation from code analysis | `lib/lang/think/generator.ex` |
| `lang.think.review_code` | ❌ | High | Automated code review with suggestions | `lib/lang/think/reviewer.ex` |
| `lang.think.estimate_complexity` | ❌ | Medium | Cognitive complexity scoring | `lib/lang/think/complexity.ex` |

## 🎨 Generative AI (`lang.generate.*`)
*Context-aware code and infrastructure generation*

| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| **Code Generation** |
| `lang.generate.from_spec` | ❌ | Critical | Natural language → working code | `lib/lang/generate/code.ex` |
| `lang.generate.from_tests` | ❌ | Critical | TDD: tests → implementation | `lib/lang/generate/code.ex` |
| `lang.generate.from_diagram` | ❌ | High | Architecture diagram → boilerplate | `lib/lang/generate/code.ex` |
| `lang.generate.complete_partial` | ❌ | Critical | Fill in incomplete implementations | `lib/lang/generate/code.ex` |
| `lang.generate.variations` | ❌ | High | Generate multiple solution approaches | `lib/lang/generate/code.ex` |
| `lang.generate.optimize` | ❌ | High | Current code → optimized version | `lib/lang/generate/optimizer.ex` |
| `lang.generate.parallelize` | ❌ | Medium | Sequential → parallel code | `lib/lang/generate/optimizer.ex` |
| `lang.generate.migrate` | ❌ | High | Code from language A → language B | `lib/lang/generate/migrator.ex` |
| **Infrastructure Generation** |
| `lang.generate.dockerfile` | ❌ | Critical | Generate optimized Dockerfiles | `lib/lang/generate/infrastructure.ex` |
| `lang.generate.compose` | ❌ | High | Generate docker-compose configs | `lib/lang/generate/infrastructure.ex` |
| `lang.generate.kubernetes` | ❌ | High | Generate K8s manifests | `lib/lang/generate/infrastructure.ex` |
| `lang.generate.terraform` | ❌ | High | Generate infrastructure as code | `lib/lang/generate/infrastructure.ex` |
| `lang.generate.ci_pipeline` | ❌ | High | Generate CI/CD pipelines | `lib/lang/generate/infrastructure.ex` |
| `lang.generate.gitops` | ❌ | Medium | Generate GitOps configurations | `lib/lang/generate/infrastructure.ex` |
| **Service Generation** |
| `lang.generate.service_mesh` | ❌ | High | Generate service mesh configs | `lib/lang/generate/services.ex` |
| `lang.generate.api_gateway` | ❌ | High | Generate API gateway configs | `lib/lang/generate/services.ex` |
| `lang.generate.load_balancer` | ❌ | Medium | Generate load balancer configs | `lib/lang/generate/services.ex` |
| `lang.generate.monitoring` | ❌ | High | Generate observability stack | `lib/lang/generate/services.ex` |
| **Agent-Bounded Generation** |
| `lang.generate.agent.implementation` | ❌ | Critical | Generate only in src/, lib/ | `lib/lang/generate/agent_bounded.ex` |
| `lang.generate.agent.testing` | ❌ | Critical | Generate only in test/, spec/ | `lib/lang/generate/agent_bounded.ex` |
| `lang.generate.agent.documentation` | ❌ | High | Generate only in docs/, *.md | `lib/lang/generate/agent_bounded.ex` |
| `lang.generate.agent.devops` | ❌ | High | Generate only in infrastructure/ | `lib/lang/generate/agent_bounded.ex` |
| **Cognitive-Aware Generation** |
| `lang.generate.cognitive.simple` | ❌ | Critical | Track 1: Bug fixes, simple updates | `lib/lang/generate/cognitive.ex` |
| `lang.generate.cognitive.feature` | ❌ | Critical | Track 2: Single feature, bounded | `lib/lang/generate/cognitive.ex` |
| `lang.generate.cognitive.integration` | ❌ | High | Track 3: Cross-agent coordination | `lib/lang/generate/cognitive.ex` |
| `lang.generate.cognitive.architecture` | ❌ | Medium | Track 4: System-wide changes | `lib/lang/generate/cognitive.ex` |
| **Pattern-Based Generation** |
| `lang.generate.from_patterns` | ❌ | Critical | Generate matching team patterns | `lib/lang/generate/patterns.ex` |
| `lang.generate.respect_boundaries` | ❌ | Critical | Never cross agent boundaries | `lib/lang/generate/patterns.ex` |
| `lang.generate.maintain_style` | ❌ | High | Match directory-specific style | `lib/lang/generate/patterns.ex` |
| `lang.generate.learn_patterns` | ❌ | High | Extract and learn from success | `lib/lang/generate/patterns.ex` |

## ⚡ Hypersonic Navigation (`lang.spatial.*`) → [`ai-first-domains.md`](./lsp/ai-first-domains.md#-langspatial---hypersonic-navigation-domain)
*Multi-dimensional code traversal at AI speed*

| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.spatial.map` | ❌ | Critical | Build 3D mental model of codebase | `lib/lang/spatial/mapper.ex` |
| `lang.spatial.traverse` | ❌ | Critical | Navigate entire codebase in seconds | `lib/lang/spatial/navigator.ex` |
| `lang.spatial.waypoint_set` | ❌ | High | Set persistent navigation markers | `lib/lang/spatial/waypoints.ex` |
| `lang.spatial.waypoint_jump` | ❌ | High | Instant jump to waypoints | `lib/lang/spatial/waypoints.ex` |
| `lang.spatial.trace_path` | ❌ | High | Visual path through call chains | `lib/lang/spatial/tracer.ex` |
| `lang.spatial.find_related` | ❌ | High | Find spatially related code | `lib/lang/spatial/relations.ex` |

## 🤖 Agent Coordination & Security (`lang.agent.*`) → [`ai-first-domains.md`](./lsp/ai-first-domains.md#-langagent---multi-agent-coordination-domain) | [`acg-protocol.md`](./lsp/acg-protocol.md)
*Multi-agent orchestration with rogue detection*

| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| **Agent Lifecycle** |
| `lang.agent.spawn` | ❌ | Critical | Create agent with specific capabilities | `lib/lang/agent/lifecycle.ex` |
| `lang.agent.delegate` | ❌ | Critical | Delegate task to agent | `lib/lang/agent/coordinator.ex` |
| `lang.agent.coordinate` | ❌ | High | Coordinate multiple agents | `lib/lang/agent/coordinator.ex` |
| `lang.agent.merge_results` | ❌ | High | Merge findings from multiple agents | `lib/lang/agent/merger.ex` |
| `lang.agent.terminate` | ❌ | Medium | Clean agent shutdown | `lib/lang/agent/lifecycle.ex` |
| `lang.agent.get_status` | ❌ | Medium | Check agent status | `lib/lang/agent/monitor.ex` |
| **Agent Security & Monitoring** |
| `lang.agent.scan` | ❌ | Critical | Scan another agent's behavior and patterns | `lib/lang/agent/security.ex` |
| `lang.agent.verify_profile` | ❌ | Critical | Check agent against expected behavior profile | `lib/lang/agent/security.ex` |
| `lang.agent.detect_rogue` | ❌ | Critical | Identify rogue/compromised agents | `lib/lang/agent/security.ex` |
| `lang.agent.quarantine` | ❌ | Critical | Isolate suspicious agent | `lib/lang/agent/security.ex` |
| `lang.agent.behavior_baseline` | ❌ | High | Establish normal behavior patterns | `lib/lang/agent/behavioral.ex` |
| `lang.agent.anomaly_score` | ❌ | High | Calculate deviation from expected behavior | `lib/lang/agent/behavioral.ex` |
| `lang.agent.trust_level` | ❌ | High | Assign trust score to agent | `lib/lang/agent/trust.ex` |
| `lang.agent.audit_trail` | ❌ | High | Full audit log of agent actions | `lib/lang/agent/audit.ex` |
| **Resource Management** |
| `lang.agent.track_usage` | ❌ | High | Track token/resource usage per agent | `lib/lang/agent/resources.ex` |
| `lang.agent.limit_resources` | ❌ | High | Set resource limits for agent | `lib/lang/agent/resources.ex` |
| `lang.agent.monitor_performance` | ❌ | Medium | Real-time performance monitoring | `lib/lang/agent/monitor.ex` |

## ⏰ Time Machine (`lang.timeline.*`)
*Code evolution and historical intelligence*

| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.timeline.evolution` | ❌ | High | How code evolved over time | `lib/lang/timemachine/evolution.ex` |
| `lang.timeline.blame_semantic` | ❌ | High | Who introduced this concept (not line) | `lib/lang/timemachine/semantic_blame.ex` |
| `lang.timeline.predict_changes` | ❌ | High | Predict likely future changes | `lib/lang/timemachine/predictor.ex` |
| `lang.timeline.find_decisions` | ❌ | Medium | Key architectural decision points | `lib/lang/timemachine/decisions.ex` |
| `lang.timeline.regression_risk` | ❌ | High | What might break if changed | `lib/lang/timemachine/risk.ex` |

## 💾 Token Optimization (`lang.tokens.*`) → [`ai-first-domains.md`](./lsp/ai-first-domains.md#-langtokens---token-optimization-domain)
*Critical for AI efficiency*

| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.tokens.estimate` | ❌ | Critical | Estimate operation token cost | `lib/lang/tokens/estimator.ex` |
| `lang.tokens.compress` | ❌ | Critical | Compress context intelligently | `lib/lang/tokens/compressor.ex` |
| `lang.tokens.filter` | ❌ | Critical | Filter by relevance | `lib/lang/tokens/filter.ex` |
| `lang.tokens.stream` | ❌ | Critical | Stream only deltas | `lib/lang/tokens/streamer.ex` |
| `lang.tokens.cache_strategy` | ❌ | High | Optimize caching for tokens | `lib/lang/tokens/cache.ex` |

## 🔍 Natural Query (`lang.query.*`) → [`ai-first-domains.md`](./lsp/ai-first-domains.md#-langquery---natural-language-query-domain)
*Natural language code queries*

| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.query.natural` | ❌ | Critical | Natural language queries | `lib/lang/query/natural.ex` |
| `lang.query.impact` | ❌ | Critical | "What breaks if I change X?" | `lib/lang/query/impact.ex` |
| `lang.query.dependency` | ❌ | High | "What depends on this?" | `lib/lang/query/dependency.ex` |
| `lang.query.ownership` | ❌ | Medium | "Who owns this code?" | `lib/lang/query/ownership.ex` |

## 🔌 Storage Integration (`lang.storage.*`)
*Bridge to Kyozo Store for persistence and memory*

| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| **Connection Management** |
| `lang.storage.connect` | ❌ | Critical | Establish connection to Kyozo Store | `lib/lang/storage/connection.ex` |
| `lang.storage.validate_auth` | ❌ | Critical | Validate shared auth token with Kyozo | `lib/lang/storage/connection.ex` |
| `lang.storage.get_status` | ❌ | High | Check Kyozo connection health | `lib/lang/storage/connection.ex` |
| **Agent Memory Operations** |
| `lang.storage.get_patterns` | ❌ | Critical | Retrieve agent patterns from Kyozo | `lib/lang/storage/patterns.ex` |
| `lang.storage.store_patterns` | ❌ | Critical | Persist learned patterns to Kyozo | `lib/lang/storage/patterns.ex` |
| `lang.storage.update_confidence` | ❌ | High | Update pattern confidence scores | `lib/lang/storage/patterns.ex` |
| `lang.storage.search_patterns` | ❌ | High | Semantic search across stored patterns | `lib/lang/storage/patterns.ex` |
| **User Context Operations** |
| `lang.storage.get_user_context` | ❌ | Critical | Load user preferences and history | `lib/lang/storage/context.ex` |
| `lang.storage.update_user_context` | ❌ | High | Update user context in Kyozo | `lib/lang/storage/context.ex` |
| `lang.storage.get_project_context` | ❌ | High | Load project-specific context | `lib/lang/storage/context.ex` |
| **Session Workspace** |
| `lang.storage.create_session` | ❌ | Critical | Create new session workspace | `lib/lang/storage/session.ex` |
| `lang.storage.sync_session` | ❌ | Critical | Sync active session with Kyozo | `lib/lang/storage/session.ex` |
| `lang.storage.get_session` | ❌ | High | Retrieve session workspace | `lib/lang/storage/session.ex` |
| `lang.storage.close_session` | ❌ | Medium | Clean up session workspace | `lib/lang/storage/session.ex` |
| **Scratch Pipeline** |
| `lang.storage.create_scratch` | ❌ | High | Create temporary scratch pipeline | `lib/lang/storage/scratch.ex` |
| `lang.storage.update_scratch` | ❌ | High | Update scratch transformation stage | `lib/lang/storage/scratch.ex` |
| `lang.storage.get_scratch` | ❌ | High | Retrieve scratch pipeline data | `lib/lang/storage/scratch.ex` |
| `lang.storage.cleanup_scratch` | ❌ | Medium | TTL-based scratch cleanup | `lib/lang/storage/scratch.ex` |

## 📊 Knowledge Graph (`lang.graph.*`)
*Semantic relationship mapping - KEEP EXISTING*

| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.graph.build` | 🚧 | High | Build knowledge graph | `lib/kyozo/lang/universal_parser/knowledge_graph.ex` |
| `lang.graph.query` | 🚧 | High | Query knowledge graph | `lib/lang/graph_reasoner.ex` |
| `lang.graph.traverse` | 🚧 | Medium | Graph traversal | Native NIF `graph_reasoner` |
| `lang.graph.update` | ❌ | Medium | Update graph nodes/edges | _Not implemented_ |
| `lang.graph.visualize` | ❌ | Low | Visualize graph | _Not implemented_ |

## 🚀 Core Infrastructure

### Filesystem Operations (`lang.fs.*`) → [`implementation-reference.md`](./lsp/implementation-reference.md#filesystem-intelligence)
| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.fs.scan` | ✅ | Critical | Directory tree scanning | `lib/lang/rpc/router.ex:56` → `lib/lang/native/fs_scanner.ex:57` |
| `lang.fs.search` | ✅ | Critical | Regex text search | `lib/lang/rpc/router.ex:86` → `lib/lang/native/fs_scanner.ex:118` |
| `lang.fs.search_code` | ✅ | Critical | Tree-sitter code search | `lib/lang/rpc/router.ex:107` → `lib/lang/native/fs_scanner.ex:170` |
| `lang.fs.preview` | ✅ | Critical | File content preview | `lib/lang/rpc/router.ex:39` → `lib/lang/native/fs_scanner.ex:208` |
| `lang.fs.watch` | 🚧 | High | File system watching | `lib/lang/native/fs_watcher.ex` |

### Universal Parser (`lang.parser.*`) → [`implementation-reference.md`](./lsp/implementation-reference.md#universal-text-parser-extensions)
| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.parser.parse` | ✅ | Critical | Universal text parsing | `lib/kyozo/lang/universal_parser.ex:146` |
| `lang.parser.parse_batch` | ✅ | High | Batch document parsing | `lib/kyozo/lang/universal_parser.ex:183` |
| `lang.parser.parse_stream` | ✅ | High | Streaming parser | `lib/kyozo/lang/universal_parser.ex:252` |
| `lang.parser.detect_format` | ✅ | Critical | Auto-detect text format | `lib/kyozo/lang/universal_parser.ex:303` |

### Workspace Management (`lang.workspace.*`) → [`implementation-reference.md`](./lsp/implementation-reference.md#workspace-management)
| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.workspace.create` | ✅ | Critical | Create analysis workspace | `lib/lang/workspace/workspace.ex` |
| `lang.workspace.load` | ✅ | Critical | Load existing workspace | `lib/lang/workspace/workspace.ex` |
| `lang.workspace.save` | ✅ | High | Save workspace state | `lib/lang/workspace/store.ex` |
| `lang.workspace.context` | 🚧 | High | Get workspace context | `lib/lang/workspace/store.ex` |

### Document Analysis (`lang.analyze.*`) → [`implementation-reference.md`](./lsp/implementation-reference.md#text-intelligence)
| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.analyze.document` | 🚧 | Critical | Analyze single document | `lib/lang/text_intelligence/analysis_engine.ex:10` |
| `lang.analyze.batch` | 🚧 | High | Analyze multiple documents | `lib/lang/text_intelligence/analysis_engine.ex:28` |
| `lang.analyze.stream` | ❌ | High | Streaming analysis | _Not implemented_ |

### Orchestration (`lang.orchestration.*`) → [`implementation-reference.md`](./lsp/implementation-reference.md#orchestration--distributed-processing)
| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.orchestration.start` | ✅ | Critical | Launch distributed analysis | `lib/lang/orchestration/master.ex:160` |
| `lang.orchestration.status` | ✅ | High | Monitor progress | `lib/lang/orchestration/master.ex:96` |
| `lang.orchestration.cancel` | ❌ | Medium | Cancel running jobs | _Not implemented_ |

### Core RPC (`rpc.*`) → [`implementation-reference.md`](./lsp/implementation-reference.md#core-rpc-methods)
| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `rpc.ping` | ✅ | High | Health check | `lib/lang/rpc/router.ex:6` |
| `rpc.initialize` | ✅ | Critical | Initialize LANG capabilities | `lib/lang/rpc/router.ex:10` |
| `rpc.shutdown` | ✅ | Critical | Clean shutdown | `lib/lang/rpc/router.ex:33` |

## Standard LSP Protocol Support → [`implementation-reference.md`](./lsp/implementation-reference.md#standard-lsp-protocol-methods)
*For editor compatibility - LOWER PRIORITY*

### Document Synchronization (`textDocument/*`)
| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `textDocument/didOpen` | 🚧 | Medium | Document opened | `lib/lang/lsp/server.ex:444` |
| `textDocument/didChange` | 🚧 | Medium | Document changed | `lib/lang/lsp/server.ex:474` |
| `textDocument/didClose` | 🚧 | Low | Document closed | `lib/lang/lsp/server.ex:511` |
| `textDocument/completion` | 🚧 | Medium | Code completion | `lib/lang/lsp/server.ex:399` |
| `textDocument/hover` | 🚧 | Medium | Hover info | `lib/lang/lsp/server.ex:413` |
| `textDocument/definition` | ❌ | Low | Go to definition | _Not implemented_ |
| `textDocument/references` | ❌ | Low | Find references | _Not implemented_ |
| `textDocument/documentSymbol` | ❌ | Low | Document outline | _Not implemented_ |
| `textDocument/formatting` | ❌ | Low | Format document | _Not implemented_ |

### Workspace Operations (`workspace/*`)
| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `workspace/symbol` | ❌ | Low | Workspace symbol search | _Not implemented_ |
| `workspace/executeCommand` | ❌ | Low | Execute commands | _Not implemented_ |

## MCP Integration (`mcp.*`) → [`implementation-reference.md`](./lsp/implementation-reference.md#mcp-integration)
| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `mcp.connection.create` | ✅ | High | Create MCP connection | `lib/lang/rpc/router.ex:121` |
| `mcp.connection.status` | ✅ | Medium | Check connection status | `lib/lang/rpc/router.ex:128` |
| `mcp.connection.destroy` | ✅ | Medium | Destroy connection | `lib/lang/rpc/router.ex:135` |

## Metrics & Monitoring (`lang.metrics.*`)
| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.metrics.performance` | 🚧 | High | System performance metrics | `lib/lang/telemetry/metrics.ex` |
| `lang.metrics.usage` | 🚧 | High | API usage statistics | `lib/lang/accounts/api_usage_logger.ex:60` |
| `lang.metrics.tokens` | ❌ | Critical | Token consumption tracking | `lib/lang/metrics/tokens.ex` |
| `lang.metrics.agent_efficiency` | ❌ | High | Agent resource usage | `lib/lang/metrics/agent_efficiency.ex` |

## Security (`lang.security.*`)
| Method | Status | Priority | Description | Implementation File |
|--------|--------|----------|-------------|-------------------|
| `lang.security.validate` | 🚧 | Critical | Request validation | `lib/lang/security/input_validator.ex:78` |
| `lang.security.sanitize` | 🚧 | Critical | Input sanitization | `lib/lang/security/input_validator.ex` |
| `lang.security.rate_limit` | ❌ | High | Rate limiting | `lib/lang/security/rate_limiter.ex` |

---

## Examples

### JSON-RPC (LSP)

- Traverse
```
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "lang.spatial.traverse",
  "params": {
    "project_id": "<project>",
    "file": "lib/app.ex",
    "depth": 2,
    "language": "elixir",
    "types": "import,use",
    "kinds": "function,module"
  }
}
```

- Trace Path
```
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "lang.spatial.trace_path",
  "params": {"project_id": "<project>", "from": "lib/a.ex", "to": "lib/b.ex", "language": "elixir", "types": "import"}
}
```

- Find Related
```
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "lang.spatial.find_related",
  "params": {"project_id": "<project>", "file": "lib/a.ex", "language": "elixir", "types": "import", "top_n": 20}
}
```

### REST

- Map Summary
```
GET /api/v2/spatial/map/<project_id>?section=all&languages=elixir&types=import&kinds=function&page=1&page_size=50
```

- Traverse
```
GET /api/v2/spatial/traverse/<project_id>?file=lib/a.ex&depth=2&language=elixir&types=import&kinds=function
```

- Trace Path
```
GET /api/v2/spatial/trace_path/<project_id>?from=lib/a.ex&to=lib/b.ex&language=elixir&types=import
```

- Find Related
```
GET /api/v2/spatial/find_related/<project_id>?file=lib/a.ex&language=elixir&types=import&top_n=20
```


- Think: Explain Intent
```
{
  "jsonrpc": "2.0",
  "id": 10,
  "method": "lang.think.explain_intent",
  "params": {"input": {"code": "def foo, do: :ok"}, "user_id": "<user>", "project_id": "<project>"}
}
```

- Generate: Complete Partial
```
{
  "jsonrpc": "2.0",
  "id": 11,
  "method": "lang.generate.complete_partial",
  "params": {"inputs": {"snippet": "def foo"}, "boundaries": {}, "user_id": "<user>", "project_id": "<project>"}
}
```


- Responses (Queued)
```
// Think: Explain Intent
{"jsonrpc":"2.0","id":10,"result":{"request_id":"<uuid>","status":"queued"}}

// Generate: Complete Partial
{"jsonrpc":"2.0","id":11,"result":{"request_id":"<uuid>","status":"queued"}}
```


### Response Shapes

- Traverse Result
```
{
  "start": "lib/app.ex",
  "depth": 2,
  "nodes": [ {"file": "lib/app.ex"}, {"file": "lib/foo.ex"} ],
  "edges": [ {"from": "lib/app.ex", "to": "lib/foo.ex", "type": "import", "language": "elixir", "target_kind": "path"} ],
  "symbols": { // present only when kinds provided
    "lib/app.ex": [ {"kind": "function", "name": "foo", "line": 10, "language": "elixir"} ]
  }
}
```

- Trace Path Result
```
{
  "from": "lib/a.ex",
  "to": "lib/b.ex",
  "nodes": [ {"file": "lib/a.ex"}, {"file": "lib/b.ex"} ],
  "edges": [ {"from": "lib/a.ex", "to": "lib/b.ex", "type": "import", "language": "elixir"} ]
}
```

- Find Related Result
```
{
  "file": "lib/a.ex",
  "related": [ {"node": "lib/b.ex", "score": 3, "via": "lib/x.ex"} ]
}
```
