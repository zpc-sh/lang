# LANG Locker - API Integration Layer - Work Item

**Status**: 🔄 Planning
**Priority**: High
**Estimated Effort**: 2-3 weeks
**Dependencies**: Kyozo Core Storage Engine, LANG API v2, Phoenix Authentication

## Overview

Implement the API integration layer for the Agent Personal Storage System (LANG Locker). This work item focuses on the **LANG platform's role** in providing API endpoints, authentication, and orchestration for agent locker functionality, while the actual storage engine is implemented in **Kyozo Core**.

## Domain Separation

**LANG Responsibilities** (This Work Item):
- API endpoints and request/response handling
- Authentication and authorization
- Agent session management
- Real-time updates via Phoenix PubSub
- Integration with existing LANG workflows

**Kyozo Core Responsibilities** (Separate Work Item):
- Persistent storage engine and data models
- JSON-LD schema management
- Search and retrieval algorithms
- Data encryption and security
- Storage optimization and caching

## Core Features

### 1. Agent Locker API Endpoints

**Agent Memory Management:**
```
POST /api/v2/locker/agent/{agent_id}/store
GET /api/v2/locker/agent/{agent_id}/patterns
PUT /api/v2/locker/agent/{agent_id}/patterns/{pattern_id}
DELETE /api/v2/locker/agent/{agent_id}/patterns/{pattern_id}
```

**User Context Management:**
```
POST /api/v2/locker/user/preferences
GET /api/v2/locker/user/context/{project_id}
PUT /api/v2/locker/user/context/{project_id}
```

**Session Workspace:**
```
POST /api/v2/locker/session/workspace
GET /api/v2/locker/session/{session_id}/memory
PUT /api/v2/locker/session/{session_id}/memory
```

**Scratch Pipeline Management:**
```
POST /api/v2/locker/scratch/pipeline
GET /api/v2/locker/scratch/{pipeline_id}/stage/{stage_id}
PUT /api/v2/locker/scratch/{pipeline_id}/stage/{stage_id}
DELETE /api/v2/locker/scratch/{pipeline_id}
```

### 2. Authentication & Authorization

**Agent Authentication:**
```elixir
defmodule LangWeb.Plugs.AgentAuthPlug do
  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "x-agent-id") do
      [agent_id] when is_binary(agent_id) ->
        assign(conn, :current_agent, agent_id)
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Agent authentication required"})
        |> halt()
    end
  end
end
```

**Access Control:**
- Agents can only access their own memory stores
- Users can only access their own context and sessions
- Session workspaces are scoped to user+agent pairs
- Scratch pipelines have TTL-based cleanup

### 3. Real-time Agent Memory Updates

**PubSub Integration:**
```elixir
defmodule LangWeb.LockerChannel do
  use Phoenix.Channel

  def join("agent:" <> agent_id, _payload, socket) do
    # Verify agent permission
    if authorized_agent?(socket, agent_id) do
      {:ok, assign(socket, :agent_id, agent_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("update_pattern", payload, socket) do
    agent_id = socket.assigns.agent_id

    case Kyozo.AgentMemory.update_pattern(agent_id, payload) do
      {:ok, updated_pattern} ->
        broadcast(socket, "pattern_updated", updated_pattern)
        {:reply, {:ok, updated_pattern}, socket}
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end
end
```

### 4. Integration with LANG Workflows

**Analysis Session Integration:**
```elixir
defmodule LangWeb.Api.V2.TextController do
  # Enhanced with locker integration
  def analyze(conn, params) do
    agent_id = get_agent_id(conn)
    user_id = conn.assigns.current_user.id

    # Retrieve relevant context from locker
    context = LockerService.get_analysis_context(agent_id, user_id, params["content"])

    # Perform analysis with context
    case perform_analysis_with_context(params, context) do
      {:ok, result} ->
        # Store learned patterns
        LockerService.store_analysis_insights(agent_id, result.insights)

        # Update user project context
        LockerService.update_user_context(user_id, result.project_context)

        render(conn, "analyze_result.json", result: result)
    end
  end
end
```

**Multi-Agent Orchestration Integration:**
```elixir
defmodule Lang.Orchestration.WorkflowEngine do
  def execute_with_context(workflow_plan, session_id) do
    # Load agent contexts
    agent_contexts = load_agent_contexts(workflow_plan.agents)

    # Execute with enhanced context
    results = execute_workflow_with_context(workflow_plan, agent_contexts)

    # Store collaboration insights
    store_collaboration_insights(session_id, results)

    results
  end
end
```

## API Controller Implementation

### Locker Controller
```elixir
defmodule LangWeb.Api.V2.LockerController do
  use LangWeb, :controller

  action_fallback LangWeb.Api.FallbackController

  # Agent memory endpoints
  def store_agent_pattern(conn, %{"agent_id" => agent_id} = params) do
    with :ok <- verify_agent_permission(conn, agent_id),
         {:ok, pattern} <- LockerService.store_pattern(agent_id, params["pattern"]) do

      # Broadcast update to agent subscribers
      Phoenix.PubSub.broadcast(Lang.PubSub, "agent:#{agent_id}",
        {:pattern_stored, pattern})

      render(conn, "pattern.json", pattern: pattern)
    end
  end

  def get_agent_patterns(conn, %{"agent_id" => agent_id} = params) do
    with :ok <- verify_agent_permission(conn, agent_id),
         {:ok, patterns} <- LockerService.get_patterns(agent_id, params) do
      render(conn, "patterns.json", patterns: patterns)
    end
  end

  # User context endpoints
  def update_user_context(conn, params) do
    user_id = conn.assigns.current_user.id

    case LockerService.update_user_context(user_id, params["context"]) do
      {:ok, context} ->
        render(conn, "user_context.json", context: context)
      {:error, reason} ->
        handle_error(conn, reason)
    end
  end

  # Scratch workspace endpoints
  def create_scratch_pipeline(conn, params) do
    user_id = conn.assigns.current_user.id
    agent_id = get_agent_id(conn)

    case LockerService.create_scratch_pipeline(user_id, agent_id, params) do
      {:ok, pipeline} ->
        # Set up TTL cleanup
        schedule_pipeline_cleanup(pipeline.id, params["ttl"] || 3600)

        render(conn, "scratch_pipeline.json", pipeline: pipeline)
    end
  end

  def get_scratch_stage(conn, %{"pipeline_id" => pipeline_id, "stage_id" => stage_id}) do
    with {:ok, stage_data} <- LockerService.get_scratch_stage(pipeline_id, stage_id),
         :ok <- verify_scratch_access(conn, pipeline_id) do
      render(conn, "scratch_stage.json", stage: stage_data)
    end
  end

  # Smart search endpoint
  def search_locker(conn, params) do
    agent_id = get_agent_id(conn)
    user_id = conn.assigns.current_user.id

    search_params = %{
      query: params["query"],
      scope: determine_search_scope(agent_id, user_id, params["scope"]),
      max_results: min(params["max_results"] || 10, 50)
    }

    case LockerService.semantic_search(search_params) do
      {:ok, results} ->
        render(conn, "search_results.json", results: results)
    end
  end

  # Helper functions
  defp verify_agent_permission(conn, agent_id) do
    case get_agent_id(conn) do
      ^agent_id -> :ok
      _ -> {:error, :unauthorized}
    end
  end

  defp get_agent_id(conn) do
    conn.assigns[:current_agent] || "unknown"
  end
end
```

## Service Layer Implementation

### Locker Service
```elixir
defmodule Lang.LockerService do
  @moduledoc """
  LANG's integration service for agent locker functionality.
  Delegates storage operations to Kyozo Core.
  """

  # Agent memory operations
  def store_pattern(agent_id, pattern_data) do
    Kyozo.AgentMemory.store_pattern(agent_id, pattern_data)
  end

  def get_patterns(agent_id, filters \\ %{}) do
    Kyozo.AgentMemory.get_patterns(agent_id, filters)
  end

  def get_analysis_context(agent_id, user_id, content_hint) do
    # Combine agent patterns + user context for analysis
    agent_patterns = Kyozo.AgentMemory.find_relevant_patterns(agent_id, content_hint)
    user_context = Kyozo.UserContext.get_active_context(user_id)

    %{
      agent_patterns: agent_patterns,
      user_context: user_context,
      content_hint: content_hint
    }
  end

  # User context operations
  def update_user_context(user_id, context_data) do
    Kyozo.UserContext.update_context(user_id, context_data)
  end

  # Session workspace operations
  def create_session_workspace(user_id, agent_id, initial_data) do
    Kyozo.SessionWorkspace.create(user_id, agent_id, initial_data)
  end

  # Scratch pipeline operations
  def create_scratch_pipeline(user_id, agent_id, pipeline_data) do
    Kyozo.ScratchPipeline.create(user_id, agent_id, pipeline_data)
  end

  def get_scratch_stage(pipeline_id, stage_id) do
    Kyozo.ScratchPipeline.get_stage(pipeline_id, stage_id)
  end

  # Smart search
  def semantic_search(search_params) do
    Kyozo.Search.semantic_search(search_params)
  end

  # Learning integration
  def store_analysis_insights(agent_id, insights) do
    Task.async(fn ->
      Kyozo.AgentMemory.store_insights(agent_id, insights)
    end)
  end

  def store_collaboration_insights(session_id, collaboration_data) do
    Task.async(fn ->
      Kyozo.SessionWorkspace.store_insights(session_id, collaboration_data)
    end)
  end
end
```

## JSON Response Views

### Locker JSON Views
```elixir
defmodule LangWeb.Api.V2.LockerView do
  use LangWeb, :view

  def render("pattern.json", %{pattern: pattern}) do
    %{
      id: pattern.id,
      type: pattern.type,
      confidence: pattern.confidence,
      usage_count: pattern.usage_count,
      data: pattern.data,
      created_at: pattern.created_at,
      last_accessed: pattern.last_accessed
    }
  end

  def render("patterns.json", %{patterns: patterns}) do
    %{
      patterns: Enum.map(patterns, &render("pattern.json", %{pattern: &1})),
      total: length(patterns)
    }
  end

  def render("user_context.json", %{context: context}) do
    %{
      preferences: context.preferences,
      project_contexts: context.project_contexts,
      collaboration_history: context.collaboration_history,
      updated_at: context.updated_at
    }
  end

  def render("scratch_pipeline.json", %{pipeline: pipeline}) do
    %{
      pipeline_id: pipeline.id,
      stages: pipeline.stages,
      ttl_expires_at: pipeline.ttl_expires_at,
      created_at: pipeline.created_at
    }
  end

  def render("search_results.json", %{results: results}) do
    %{
      results: Enum.map(results, &format_search_result/1),
      total: length(results)
    }
  end

  defp format_search_result(result) do
    %{
      type: result.type,
      content: result.content,
      relevance_score: result.relevance_score,
      source: result.source,
      context: result.context
    }
  end
end
```

## Integration Tasks

### Phase 1: API Infrastructure (Week 1)
- [ ] Create LockerController with basic endpoints
- [ ] Implement agent authentication middleware
- [ ] Add JSON response views
- [ ] Create LockerService integration layer
- [ ] Set up Phoenix PubSub channels for real-time updates

### Phase 2: Workflow Integration (Week 2)
- [ ] Integrate locker with text analysis endpoints
- [ ] Add context loading to multi-agent orchestration
- [ ] Implement scratch pipeline TTL management
- [ ] Create smart search functionality
- [ ] Add learning insights storage

### Phase 3: Advanced Features (Week 2-3)
- [ ] Real-time agent memory synchronization
- [ ] Context-aware API responses
- [ ] Performance optimization and caching
- [ ] Analytics and usage tracking
- [ ] Error handling and recovery

## Router Configuration

```elixir
# lib/lang_web/router.ex
scope "/api/v2/locker", LangWeb.Api.V2 do
  pipe_through [:api, :require_authenticated_api, :agent_auth]

  # Agent memory routes
  post "/agent/:agent_id/patterns", LockerController, :store_agent_pattern
  get "/agent/:agent_id/patterns", LockerController, :get_agent_patterns
  put "/agent/:agent_id/patterns/:pattern_id", LockerController, :update_agent_pattern
  delete "/agent/:agent_id/patterns/:pattern_id", LockerController, :delete_agent_pattern

  # User context routes
  get "/user/context", LockerController, :get_user_context
  post "/user/context", LockerController, :update_user_context
  get "/user/context/:project_id", LockerController, :get_project_context

  # Session workspace routes
  post "/session/workspace", LockerController, :create_session_workspace
  get "/session/:session_id/memory", LockerController, :get_session_memory
  put "/session/:session_id/memory", LockerController, :update_session_memory

  # Scratch pipeline routes
  post "/scratch/pipeline", LockerController, :create_scratch_pipeline
  get "/scratch/:pipeline_id/stage/:stage_id", LockerController, :get_scratch_stage
  put "/scratch/:pipeline_id/stage/:stage_id", LockerController, :update_scratch_stage
  delete "/scratch/:pipeline_id", LockerController, :delete_scratch_pipeline

  # Search routes
  post "/search", LockerController, :search_locker
end

# WebSocket channel for real-time updates
channel "agent:*", LangWeb.LockerChannel
```

## Success Metrics

### API Performance
- **Response Time**: < 100ms for context retrieval
- **Throughput**: Support 100+ concurrent agent requests
- **Cache Efficiency**: > 85% cache hit rate for patterns
- **Real-time Updates**: < 50ms latency for PubSub

### Integration Quality
- **Context Accuracy**: > 95% relevant context retrieval
- **Agent Learning**: Measurable improvement in response quality
- **User Experience**: Seamless context continuity across sessions
- **Error Handling**: > 99.9% API reliability

## Dependencies on Kyozo Core

This LANG work item depends on Kyozo Core implementing:

### Storage Engine
- `Kyozo.AgentMemory` - Agent pattern storage and retrieval
- `Kyozo.UserContext` - User preference and project context storage
- `Kyozo.SessionWorkspace` - Active session memory management
- `Kyozo.ScratchPipeline` - Temporary transformation storage

### Search & Intelligence
- `Kyozo.Search` - Semantic search across all locker data
- Pattern matching and similarity algorithms
- JSON-LD schema validation and processing
- Data encryption and security layers

### Performance & Scaling
- Intelligent caching strategies
- Storage optimization
- Query performance tuning
- Data compression and archival

---

**Next Steps**:
1. Coordinate with Kyozo Core team on storage interface design
2. Begin Phase 1 implementation once Kyozo storage engine is ready
3. Create integration tests to validate agent locker functionality
4. Plan deployment strategy for both LANG API and Kyozo storage

The LANG Locker API will transform agent interactions by providing persistent memory and intelligent context awareness! 🧠🚀
