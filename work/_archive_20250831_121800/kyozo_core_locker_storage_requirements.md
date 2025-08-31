# Kyozo Core - Agent Locker Storage Engine Requirements

**Target**: `../kyozo_core/works/agent_locker_storage.md`
**Status**: Requirements Document
**Priority**: High
**Estimated Effort**: 3-4 weeks
**Dependencies**: None (Core storage system)

## Overview

This document outlines the storage engine requirements for the Agent Personal Locker System. Kyozo Core is responsible for all persistent storage, data models, search algorithms, and security for agent memory, user context, and session workspaces.

## Domain Responsibility

**Kyozo Core owns all storage concerns:**
- Persistent data storage and retrieval
- JSON-LD schema management and validation
- Search algorithms and indexing
- Data encryption and security
- Performance optimization and caching
- Database schema design and migrations

**LANG handles API integration:**
- HTTP endpoints and authentication
- Phoenix PubSub real-time updates
- Integration with analysis workflows
- Request/response processing

## Storage Architecture Requirements

### Three-Tier Storage Model

```
/kyozo_storage/
  /agent_memory/           # Cross-user agent learning (shared knowledge)
    /claude/
      patterns.jsonld       # "Phoenix apps usually have this structure"
      templates.jsonld      # Personal analysis frameworks
      expertise.jsonld      # Domain knowledge evolution

  /user_context/           # User-specific persistent data
    /user_123/
      preferences.jsonld    # Communication style and technical background
      projects.jsonld       # Project context and collaboration history
      api_keys.encrypted    # External service credentials

  /session_workspace/      # Active collaboration workspace
    /user:123:agent:claude/
      working_memory.jsonld # Current project understanding
      scratch_pipelines/    # Multi-stage transformation storage
        pipeline_abc.jsonld # TTL-managed intermediate results
```

## Core Storage Modules Required

### 1. Agent Memory Storage (`Kyozo.AgentMemory`)

**Pattern Storage with Intelligence:**
```elixir
defmodule Kyozo.AgentMemory do
  @moduledoc """
  Manages agent learning patterns and domain expertise evolution.
  Enables agents to learn and improve across sessions and users.
  """

  def store_pattern(agent_id, pattern_data) do
    # Store with confidence scoring and usage tracking
  end

  def get_patterns(agent_id, filters \\ %{}) do
    # Retrieve with relevance ranking
  end

  def find_relevant_patterns(agent_id, context_hint) do
    # Semantic search for contextually relevant patterns
  end

  def update_pattern_confidence(pattern_id, success_feedback) do
    # Machine learning-style confidence updates
  end

  def store_insights(agent_id, analysis_insights) do
    # Extract and store patterns from successful analyses
  end
end
```

**Required JSON-LD Schema:**
```json
{
  "@context": "https://lang.nocsi.com/schema/v1/agent-memory",
  "@type": "LearnedPattern",
  "@id": "pattern:claude:phoenix_rust_hybrid",
  "agent_id": "claude",
  "pattern_type": "architecture_recognition",
  "confidence": 0.95,
  "usage_count": 23,
  "pattern_data": {
    "name": "phoenix_rust_hybrid",
    "recognition_signals": ["use Rustler", "Oban.Worker", "Phoenix.LiveView"],
    "performance_characteristics": "60_100x_speedup_potential",
    "common_optimizations": ["memory_mapped_files", "parallel_processing"]
  },
  "learned_from": ["session:456", "session:789"],
  "created_at": "2024-12-19T10:30:00Z",
  "last_accessed": "2024-12-19T15:45:00Z",
  "success_rate": 0.89
}
```

### 2. User Context Storage (`Kyozo.UserContext`)

**Personal Data Management:**
```elixir
defmodule Kyozo.UserContext do
  @moduledoc """
  Manages user preferences, project history, and personal data.
  Provides encrypted storage for sensitive information.
  """

  def update_context(user_id, context_data) do
    # Store with automatic encryption for sensitive fields
  end

  def get_active_context(user_id) do
    # Retrieve current user context with decryption
  end

  def get_project_context(user_id, project_id) do
    # Get specific project collaboration history
  end

  def store_collaboration_insights(user_id, session_data) do
    # Learn user preferences from successful interactions
  end
end
```

**User Context Schema:**
```json
{
  "@context": "https://lang.nocsi.com/schema/v1/user-context",
  "@type": "UserContext",
  "@id": "user:123:context",
  "user_id": "user_123",
  "preferences": {
    "communication_style": {
      "detail_level": "comprehensive",
      "code_examples": "always_include",
      "explanation_style": "technical_with_context"
    },
    "technical_background": {
      "languages": ["elixir", "rust", "javascript"],
      "frameworks": ["phoenix", "liveview", "rustler"],
      "experience_level": "senior_engineer"
    }
  },
  "projects": {
    "lang_universal_platform": {
      "last_discussed": "2024-12-19",
      "key_components": ["phoenix_web", "rust_nifs", "oban_workers"],
      "ongoing_work": ["multi_agent_orchestration", "workspace_optimization"]
    }
  }
}
```

### 3. Session Workspace Storage (`Kyozo.SessionWorkspace`)

**Active Memory Management:**
```elixir
defmodule Kyozo.SessionWorkspace do
  @moduledoc """
  Manages active session working memory and collaboration context.
  Provides session-scoped storage for current analysis state.
  """

  def create(user_id, agent_id, initial_data) do
    # Create new session workspace
  end

  def update_working_memory(session_id, memory_data) do
    # Update current analysis state
  end

  def get_session_memory(session_id) do
    # Retrieve current working context
  end

  def store_insights(session_id, collaboration_data) do
    # Store successful collaboration patterns
  end
end
```

### 4. Scratch Pipeline Storage (`Kyozo.ScratchPipeline`)

**Transformation Pipeline Management:**
```elixir
defmodule Kyozo.ScratchPipeline do
  @moduledoc """
  Manages temporary transformation pipelines with TTL cleanup.
  Enables multi-stage workflows without flooding chat channels.
  """

  def create(user_id, agent_id, pipeline_data) do
    # Create pipeline with automatic TTL cleanup
  end

  def get_stage(pipeline_id, stage_id) do
    # Retrieve specific transformation stage
  end

  def update_stage(pipeline_id, stage_id, stage_data) do
    # Update transformation stage with hash verification
  end

  def cleanup_expired_pipelines() do
    # Background cleanup of expired TTL pipelines
  end
end
```

**Pipeline Schema:**
```json
{
  "@context": "https://lang.nocsi.com/schema/v1/scratch-pipeline",
  "@type": "ScratchPipeline",
  "@id": "scratch:user:123:agent:claude:pipeline_xyz",
  "pipeline_id": "pipeline_xyz",
  "user_id": "user_123",
  "agent_id": "claude",
  "ttl_expires_at": "2024-12-19T17:30:00Z",
  "pipeline": {
    "stages": [
      {
        "id": "stage_1",
        "transform": "codebase_analysis",
        "output_hash": "sha256:abc123...",
        "output_data": {
          "architecture": "phoenix_rust_hybrid",
          "components": ["web", "nifs", "workers"],
          "optimization_opportunities": 7
        },
        "status": "completed",
        "completed_at": "2024-12-19T15:15:00Z"
      },
      {
        "id": "stage_2",
        "input_stage": "stage_1",
        "transform": "optimization_plan",
        "status": "in_progress"
      }
    ]
  }
}
```

## Search & Intelligence Engine

### 5. Semantic Search (`Kyozo.Search`)

**Advanced Search Capabilities:**
```elixir
defmodule Kyozo.Search do
  @moduledoc """
  Provides semantic search across all locker data types.
  Uses JSON-LD context for intelligent pattern matching.
  """

  def semantic_search(search_params) do
    # Cross-domain semantic search with relevance scoring
  end

  def find_similar_patterns(pattern, similarity_threshold \\ 0.8) do
    # Pattern similarity matching for agent learning
  end

  def contextual_search(query, user_context, agent_context) do
    # Search with user and agent context for better relevance
  end
end
```

**Search Features Required:**
- **Cross-domain search** - Search across agent, user, and session data
- **Semantic similarity** - JSON-LD aware pattern matching
- **Relevance scoring** - Context-aware result ranking
- **Faceted search** - Filter by data type, confidence, usage, etc.
- **Real-time indexing** - Updates search index as data is stored

## Database Schema Requirements

### Core Tables
```sql
-- Agent persistent memory
CREATE TABLE agent_memories (
  id UUID PRIMARY KEY,
  agent_id VARCHAR NOT NULL,
  pattern_id VARCHAR NOT NULL,
  pattern_type VARCHAR NOT NULL,
  content JSONB NOT NULL,
  confidence FLOAT DEFAULT 0.5,
  usage_count INTEGER DEFAULT 0,
  success_rate FLOAT DEFAULT 0.5,
  created_at TIMESTAMP DEFAULT NOW(),
  last_accessed TIMESTAMP DEFAULT NOW(),
  UNIQUE(agent_id, pattern_id),
  INDEX (agent_id, pattern_type),
  INDEX (confidence DESC),
  INDEX (usage_count DESC),
  INDEX (last_accessed DESC)
);

-- Full-text search on pattern content
CREATE INDEX agent_memories_content_gin ON agent_memories USING GIN (content);

-- User context storage
CREATE TABLE user_contexts (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  context_type VARCHAR NOT NULL,
  content JSONB NOT NULL,
  encrypted_fields TEXT, -- For sensitive data
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, context_type),
  INDEX (user_id)
);

-- Session working memory
CREATE TABLE session_workspaces (
  id UUID PRIMARY KEY,
  session_id VARCHAR UNIQUE NOT NULL,
  user_id UUID NOT NULL,
  agent_id VARCHAR NOT NULL,
  workspace_data JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  last_accessed TIMESTAMP DEFAULT NOW(),
  INDEX (session_id),
  INDEX (user_id, agent_id),
  INDEX (last_accessed DESC)
);

-- Scratch transformation pipelines
CREATE TABLE scratch_pipelines (
  id UUID PRIMARY KEY,
  pipeline_id VARCHAR UNIQUE NOT NULL,
  user_id UUID NOT NULL,
  agent_id VARCHAR NOT NULL,
  pipeline_data JSONB NOT NULL,
  ttl_expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  INDEX (pipeline_id),
  INDEX (ttl_expires_at), -- Critical for cleanup
  INDEX (user_id, agent_id)
);

-- Search and analytics
CREATE TABLE search_analytics (
  id UUID PRIMARY KEY,
  search_query VARCHAR NOT NULL,
  search_scope VARCHAR NOT NULL,
  results_count INTEGER,
  response_time_ms INTEGER,
  user_id UUID,
  agent_id VARCHAR,
  created_at TIMESTAMP DEFAULT NOW(),
  INDEX (created_at DESC),
  INDEX (search_scope),
  INDEX (response_time_ms)
);
```

## Performance & Scaling Requirements

### Caching Strategy
- **Pattern Cache** - Frequently accessed agent patterns in Redis
- **Context Cache** - Active user contexts with 1-hour TTL
- **Session Cache** - Working memory with session-based TTL
- **Search Cache** - Cached search results for common queries

### Performance Targets
- **Storage Operations**: < 50ms for CRUD operations
- **Search Performance**: < 200ms for semantic search
- **Cache Hit Rate**: > 90% for active patterns and contexts
- **TTL Cleanup**: Sub-second cleanup of expired pipelines
- **Concurrent Operations**: Support 1000+ simultaneous agent operations

### Scaling Considerations
- **Horizontal Scaling**: Design for multi-node deployment
- **Data Partitioning**: Partition by agent_id and user_id
- **Read Replicas**: Separate read/write database instances
- **Background Processing**: Async cleanup and analytics jobs

## Security & Privacy Requirements

### Data Encryption
```elixir
defmodule Kyozo.Encryption do
  @moduledoc """
  Handles encryption of sensitive data in user contexts.
  """

  def encrypt_sensitive_fields(data) do
    # Encrypt API keys, credentials, personal information
  end

  def decrypt_user_data(encrypted_data, user_id) do
    # User-scoped decryption with key derivation
  end
end
```

### Security Features Required
- **Field-level encryption** for sensitive user data
- **Agent data isolation** - Agents cannot access each other's memories
- **User data privacy** - Users cannot access other users' contexts
- **Session scoping** - Session data isolated per user+agent pair
- **Audit logging** - Track all access and modification events

### Privacy Controls
- **Data retention policies** - Configurable TTL for different data types
- **Export/import** - Users can export their personal context data
- **Selective deletion** - Users can delete specific memories or contexts
- **Opt-out mechanisms** - Users can disable context storage entirely

## Implementation Phases

### Phase 1: Core Storage Engine (Week 1-2)
- [ ] Database schema creation and migrations
- [ ] Core storage modules (`AgentMemory`, `UserContext`)
- [ ] Basic CRUD operations with JSON-LD validation
- [ ] Encryption layer for sensitive data
- [ ] TTL cleanup background jobs

### Phase 2: Search & Intelligence (Week 2-3)
- [ ] Semantic search engine implementation
- [ ] Pattern similarity algorithms
- [ ] Search indexing and optimization
- [ ] Context-aware relevance scoring
- [ ] Search analytics and monitoring

### Phase 3: Performance & Scaling (Week 3-4)
- [ ] Caching layer implementation
- [ ] Performance optimization and profiling
- [ ] Horizontal scaling preparation
- [ ] Background job optimization
- [ ] Monitoring and alerting

## Testing Requirements

### Unit Tests
- All storage modules with comprehensive test coverage
- JSON-LD schema validation testing
- Encryption/decryption functionality
- Search algorithm accuracy testing

### Integration Tests
- Full storage workflow testing
- Cache consistency validation
- TTL cleanup verification
- Performance benchmarking

### Security Tests
- Data isolation verification
- Encryption security audit
- Access control testing
- Privacy compliance validation

## Success Metrics

### Storage Performance
- **Write Operations**: < 50ms average
- **Read Operations**: < 25ms average
- **Search Operations**: < 200ms average
- **Cache Hit Rate**: > 90% for active data

### Data Quality
- **Schema Validation**: 100% JSON-LD compliance
- **Data Integrity**: Zero data corruption incidents
- **Backup/Recovery**: < 15 minute recovery time
- **Search Accuracy**: > 95% relevant results

### Security Metrics
- **Zero data breaches** - Complete data isolation
- **Audit Compliance** - 100% tracked operations
- **Encryption Coverage** - All sensitive data encrypted
- **Privacy Compliance** - Full user control over data

## Integration Interface

### Required APIs for LANG Integration
```elixir
# Agent Memory Interface
Kyozo.AgentMemory.store_pattern(agent_id, pattern_data)
Kyozo.AgentMemory.get_patterns(agent_id, filters)
Kyozo.AgentMemory.find_relevant_patterns(agent_id, context)

# User Context Interface
Kyozo.UserContext.update_context(user_id, context_data)
Kyozo.UserContext.get_active_context(user_id)

# Session Workspace Interface
Kyozo.SessionWorkspace.create(user_id, agent_id, data)
Kyozo.SessionWorkspace.get_session_memory(session_id)

# Scratch Pipeline Interface
Kyozo.ScratchPipeline.create(user_id, agent_id, pipeline_data)
Kyozo.ScratchPipeline.get_stage(pipeline_id, stage_id)

# Search Interface
Kyozo.Search.semantic_search(search_params)
```

## Deployment Considerations

### Environment Requirements
- **PostgreSQL 14+** with JSONB support
- **Redis 6+** for caching layer
- **Background job processing** (Oban integration)
- **Monitoring infrastructure** (metrics and logging)

### Configuration Management
- **Database connection pooling**
- **Cache size and TTL configuration**
- **Encryption key management**
- **Background job queue configuration**

---

**Next Steps**:
1. Review storage requirements with Kyozo Core team
2. Validate JSON-LD schema design
3. Plan database migration strategy
4. Coordinate interface design with LANG team
5. Begin Phase 1 implementation

This storage engine will provide the foundational "digital brain" that transforms AI agents from stateless tools into intelligent, learning partners! 🧠⚡
