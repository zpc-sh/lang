# LSP Implementation Reference

**Complete reference for implementing the LANG LSP server with standard LSP protocol + AI agent extensions**

## Overview

The LANG LSP server implements the standard Language Server Protocol plus extensions specifically designed for AI agents to perform text intelligence, filesystem operations, and semantic analysis.

## Implementation Status Legend

- ✅ **Complete** - Fully implemented and tested
- 🚧 **Partial** - Basic implementation, needs enhancement
- ❌ **Missing** - Not implemented yet
- 🔄 **Planned** - Scheduled for implementation

---

## Standard LSP Protocol Methods

### Lifecycle Methods

| Method | Status | Priority | Description | AI Agent Use Case |
|--------|--------|----------|-------------|-------------------|
| `initialize` | ✅ | **Critical** | Initialize server with client capabilities | Establish session, get server capabilities |
| `initialized` | ❌ | High | Notification that client is ready | Complete initialization handshake |
| `shutdown` | ✅ | **Critical** | Graceful shutdown request | Clean session termination |
| `exit` | ❌ | High | Force server exit | Emergency termination |

### Document Synchronization

| Method | Status | Priority | Description | AI Agent Use Case |
|--------|--------|----------|-------------|-------------------|
| `textDocument/didOpen` | ❌ | **Critical** | Document opened in editor | Track active documents, begin analysis |
| `textDocument/didChange` | ❌ | **Critical** | Document content changed | Real-time analysis updates |
| `textDocument/didSave` | ❌ | High | Document saved to disk | Trigger comprehensive analysis |
| `textDocument/didClose` | ❌ | Medium | Document closed in editor | Clean up analysis resources |
| `textDocument/willSave` | ❌ | Low | About to save document | Pre-save validation |
| `textDocument/willSaveWaitUntil` | ❌ | Low | Wait for edits before save | Apply auto-fixes before save |

### Language Features

| Method | Status | Priority | Description | AI Agent Use Case |
|--------|--------|----------|-------------|-------------------|
| `textDocument/completion` | 🚧 | **Critical** | Code completion suggestions | Intelligent text/code completion |
| `textDocument/hover` | 🚧 | **Critical** | Hover information | Context-aware documentation |
| `textDocument/signatureHelp` | ❌ | High | Function signature help | Parameter assistance |
| `textDocument/declaration` | ❌ | High | Go to declaration | Navigate to definitions |
| `textDocument/definition` | ❌ | **Critical** | Go to definition | Code navigation |
| `textDocument/typeDefinition` | ❌ | Medium | Go to type definition | Type system navigation |
| `textDocument/implementation` | ❌ | Medium | Go to implementation | Find implementations |
| `textDocument/references` | ❌ | High | Find all references | Usage analysis |
| `textDocument/documentHighlight` | ❌ | Medium | Highlight symbol occurrences | Visual reference highlighting |
| `textDocument/documentSymbol` | ❌ | **Critical** | Document outline/symbols | Structure analysis |
| `textDocument/codeAction` | ❌ | High | Available code actions | Automated fixes/refactoring |
| `textDocument/codeLens` | ❌ | Medium | Code lens information | Inline metrics/actions |
| `textDocument/documentLink` | ❌ | Medium | Extract document links | Link validation/navigation |
| `textDocument/documentColor` | ❌ | Low | Color information | Color picker support |
| `textDocument/colorPresentation` | ❌ | Low | Color representation | Color format conversion |
| `textDocument/formatting` | ❌ | High | Format entire document | Auto-formatting |
| `textDocument/rangeFormatting` | ❌ | High | Format text range | Selective formatting |
| `textDocument/onTypeFormatting` | ❌ | Medium | Format on typing | Real-time formatting |
| `textDocument/rename` | ❌ | High | Symbol renaming | Refactoring support |
| `textDocument/foldingRange` | ❌ | Low | Code folding ranges | Editor folding support |

### Workspace Features

| Method | Status | Priority | Description | AI Agent Use Case |
|--------|--------|----------|-------------|-------------------|
| `workspace/symbol` | ❌ | **Critical** | Workspace-wide symbol search | Project-wide navigation |
| `workspace/executeCommand` | ❌ | High | Execute server commands | Trigger analysis operations |
| `workspace/applyEdit` | ❌ | High | Apply workspace edits | Batch file modifications |
| `workspace/didChangeConfiguration` | ❌ | Medium | Configuration changed | Adapt behavior to settings |
| `workspace/didChangeWatchedFiles` | ❌ | High | File system changes | Respond to external changes |
| `workspace/didCreateFiles` | ❌ | Medium | Files created | Update workspace model |
| `workspace/didRenameFiles` | ❌ | Medium | Files renamed | Update references |
| `workspace/didDeleteFiles` | ❌ | Medium | Files deleted | Clean up references |

### Diagnostics

| Method | Status | Priority | Description | AI Agent Use Case |
|--------|--------|----------|-------------|-------------------|
| `textDocument/publishDiagnostics` | ❌ | **Critical** | Send diagnostics to client | Report analysis results |

---

## LANG LSP Extensions

### Core RPC Methods

| Method | Status | Priority | Description | AI Agent Use Case | Implementation File |
|--------|--------|----------|-------------|-------------------|-------------------|
| `rpc.initialize` | ✅ | **Critical** | Initialize LANG capabilities | Get extended capabilities | `lib/lang/rpc/router.ex:10` |
| `rpc.ping` | ✅ | High | Health check | Connection testing | `lib/lang/rpc/router.ex:6` |
| `rpc.shutdown` | ✅ | **Critical** | Clean shutdown | Graceful termination | `lib/lang/rpc/router.ex:33` |
| `rpc.stream_example` | ✅ | Medium | Streaming response demo | Handle long operations | `lib/lang/rpc/router.ex:147` |

### Universal Text Parser Extensions

| Method | Status | Priority | Description | AI Agent Use Case | Implementation File |
|--------|--------|----------|-------------|-------------------|-------------------|
| `lang.parser.parse` | ✅ | **Critical** | Universal text parsing | Parse any format (JSON, YAML, Markdown, etc.) | `lib/kyozo/lang/universal_parser.ex:146` |
| `lang.parser.parse_batch` | ✅ | High | Batch document parsing | Process multiple documents | `lib/kyozo/lang/universal_parser.ex:183` |
| `lang.parser.parse_minimal` | ✅ | Medium | Minimal parsing for performance | Quick format validation | `lib/kyozo/lang/universal_parser.ex:226` |
| `lang.parser.parse_stream` | ✅ | High | Streaming parser | Handle large documents | `lib/kyozo/lang/universal_parser.ex:252` |
| `lang.parser.supported_formats` | ✅ | Medium | List supported formats | Capability discovery | `lib/kyozo/lang/universal_parser.ex:279` |
| `lang.parser.detect_format` | ✅ | **Critical** | Auto-detect text format | Format identification | `lib/kyozo/lang/universal_parser.ex:303` |
| `lang.parser.supports_format` | ✅ | Medium | Check format support | Format validation | `lib/kyozo/lang/universal_parser.ex:317` |

### Filesystem Intelligence

| Method | Status | Priority | Description | AI Agent Use Case | Implementation File |
|--------|--------|----------|-------------|-------------------|-------------------|
| `lang.fs.scan` | ✅ | **Critical** | Directory tree scanning | Get project structure | `lib/lang/rpc/router.ex:56` → `lib/lang/native/fs_scanner.ex:57` |
| `lang.fs.search` | ✅ | **Critical** | Regex text search | Find content across files | `lib/lang/rpc/router.ex:86` → `lib/lang/native/fs_scanner.ex:118` |
| `lang.fs.search_code` | ✅ | **Critical** | Tree-sitter code search | Semantic code queries | `lib/lang/rpc/router.ex:107` → `lib/lang/native/fs_scanner.ex:170` |
| `lang.fs.preview` | ✅ | **Critical** | File content preview | Quick file inspection | `lib/lang/rpc/router.ex:39` → `lib/lang/native/fs_scanner.ex:208` |
| `lang.fs.watch` | 🚧 | High | File system watching | Real-time change detection | `lib/lang/native/fs_watcher.ex` |
| `lang.fs.stats` | 🚧 | Medium | File/directory statistics | Project metrics | Native NIF functions |
| `lang.fs.bulk_read` | ❌ | High | Read multiple files | Batch file loading | _Not implemented_ |
| `lang.fs.bulk_write` | ❌ | Medium | Write multiple files | Batch modifications | _Not implemented_ |

### Text Intelligence

| Method | Status | Priority | Description | AI Agent Use Case | Implementation File |
|--------|--------|----------|-------------|-------------------|-------------------|
| `lang.analyze.document` | 🚧 | **Critical** | Analyze single document | Extract text intelligence | `lib/lang/text_intelligence/analysis_engine.ex:10` |
| `lang.analyze.batch` | 🚧 | High | Analyze multiple documents | Bulk analysis | `lib/lang/text_intelligence/analysis_engine.ex:28` |
| `lang.analyze.stream` | ❌ | High | Streaming analysis | Large document processing | _Not implemented_ |
| `lang.parse.detect_format` | ✅ | **Critical** | Auto-detect text format | Format identification | `lib/kyozo/lang/universal_parser/format_detector.ex` |
| `lang.parse.structure` | 🚧 | **Critical** | Extract document structure | Hierarchical analysis | `lib/kyozo/lang/universal_parser.ex:451` |
| `lang.parse.entities` | ❌ | High | Extract named entities | Semantic entity extraction | _Not implemented_ |
| `lang.parse.links` | ❌ | High | Extract links/references | Cross-document analysis | _Not implemented_ |
| `lang.parse.metadata` | 🚧 | Medium | Extract document metadata | Document properties | `lib/kyozo/lang/universal_parser.ex:414` |
| `lang.semantic.diff` | 🚧 | High | Semantic document diff | Intelligent comparison | `lib/lang/native/perf_engine.ex` |
| `lang.semantic.similarity` | ❌ | Medium | Document similarity | Content matching | _Not implemented_ |
| `lang.semantic.classify` | ❌ | Medium | Document classification | Content categorization | _Not implemented_ |

### Knowledge Graph

| Method | Status | Priority | Description | AI Agent Use Case | Implementation File |
|--------|--------|----------|-------------|-------------------|-------------------|
| `lang.graph.build` | 🚧 | High | Build knowledge graph | Create semantic relationships | `lib/kyozo/lang/universal_parser/knowledge_graph.ex` |
| `lang.graph.query` | 🚧 | High | Query knowledge graph | Semantic search | `lib/lang/graph_reasoner.ex` |
| `lang.graph.traverse` | 🚧 | Medium | Graph traversal | Explore relationships | Native NIF `graph_reasoner` |
| `lang.graph.update` | ❌ | Medium | Update graph nodes/edges | Maintain graph currency | _Not implemented_ |
| `lang.graph.export` | ❌ | Low | Export graph data | Data interchange | _Not implemented_ |

### MCP Integration

| Method | Status | Priority | Description | AI Agent Use Case | Implementation File |
|--------|--------|----------|-------------|-------------------|-------------------|
| `mcp.connection.create` | ✅ | **Critical** | Create MCP connection | Connect to AI services | `lib/lang/rpc/router.ex:121` → `lib/lang/rpc/mcp_handlers.ex` |
| `mcp.connection.status` | ✅ | High | Check connection status | Monitor connections | `lib/lang/rpc/router.ex:128` → `lib/lang/rpc/mcp_handlers.ex` |
| `mcp.connection.destroy` | ✅ | High | Destroy connection | Clean up resources | `lib/lang/rpc/router.ex:135` → `lib/lang/rpc/mcp_handlers.ex` |
| `mcp.connection.list` | ❌ | Medium | List active connections | Connection management | _Not implemented_ |
| `mcp.security.validate` | ❌ | High | Validate requests | Security enforcement | `lib/lang/mcp/security.ex` |
| `mcp.stream.create` | ❌ | High | Create streaming session | Real-time communication | `lib/lang/mcp/stream_bridge.ex` |

### Workspace Management

| Method | Status | Priority | Description | AI Agent Use Case | Implementation File |
|--------|--------|----------|-------------|-------------------|-------------------|
| `lang.workspace.create` | ✅ | **Critical** | Create analysis workspace | Initialize session context | `lib/lang/workspace/workspace.ex` (Ash Resource) |
| `lang.workspace.load` | ✅ | **Critical** | Load existing workspace | Resume analysis session | `lib/lang/workspace/workspace.ex` |
| `lang.workspace.save` | ✅ | High | Save workspace state | Persist session data | `lib/lang/workspace/store.ex` |
| `lang.workspace.delete` | ✅ | Medium | Delete workspace | Clean up resources | `lib/lang/workspace/workspace.ex` |
| `lang.workspace.list` | ✅ | Medium | List workspaces | Workspace management | `lib/lang/workspace/workspace.ex` |
| `lang.workspace.context` | 🚧 | High | Get workspace context | Current state information | `lib/lang/workspace/store.ex` |
| `lang.workspace.update` | 🚧 | High | Update workspace settings | Configuration management | `lib/lang/workspace/service.ex` |

### Analysis Results

| Method | Status | Priority | Description | AI Agent Use Case | Implementation File |
|--------|--------|----------|-------------|-------------------|-------------------|
| `lang.results.get` | 🚧 | **Critical** | Get analysis results | Retrieve analysis data | `lib/lang/analysis.ex` |
| `lang.results.subscribe` | ✅ | High | Subscribe to updates | Real-time result streaming | `lib/lang_web/channels/lsp_channel.ex:46` |
| `lang.results.export` | ❌ | Medium | Export results | Data portability | _Not implemented_ |
| `lang.results.compare` | ❌ | Medium | Compare result sets | Historical analysis | _Not implemented_ |
| `lang.results.filter` | ❌ | High | Filter results | Targeted data retrieval | _Not implemented_ |
| `lang.results.aggregate` | ❌ | Medium | Aggregate statistics | Summary reporting | _Not implemented_ |

### Cloud Infrastructure Intelligence

| Method | Status | Priority | Description | AI Agent Use Case | Implementation File |
|--------|--------|----------|-------------|-------------------|-------------------|
| `lang.cloud.discover` | 🚧 | **Critical** | Discover cloud resources | Map AWS/GCP/Azure infrastructure | `lib/lang/specs/jsonld.ex:78` |
| `lang.cloud.analyze_costs` | ❌ | High | Analyze cloud spending | Cost optimization insights | _Not implemented_ |
| `lang.cloud.security_scan` | ❌ | **Critical** | Security vulnerability scan | Infrastructure security audit | _Not implemented_ |
| `lang.cloud.compliance_check` | ❌ | High | Compliance validation | Regulatory compliance | _Not implemented_ |
| `lang.cloud.optimize` | ❌ | High | Resource optimization | Performance/cost recommendations | _Not implemented_ |
| `lang.cloud.monitor` | ❌ | Medium | Real-time monitoring | Infrastructure health | _Not implemented_ |

### Systems Intelligence

| Method | Status | Priority | Description | AI Agent Use Case | Implementation

### Core LSP Infrastructure
- **LSP Server**: `lib/lang/lsp/server.ex` - Main LSP TCP server
- **RPC Router**: `lib/lang/rpc/router.ex` - Method dispatch and routing
- **WebSocket Channel**: `lib/lang_web/channels/lsp_channel.ex` - Phoenix Channel integration
- **Streaming Protocol**: `lib/lang/lsp/streaming_protocol.ex` - Long-running operations

### Text Processing Engine
- **Universal Parser**: `lib/kyozo/lang/universal_parser.ex` - Main parsing interface
- **Format Registry**: `lib/lang/text_intelligence/parser_registry.ex` - Format parsers registry
- **Format Detector**: `lib/kyozo/lang/universal_parser/format_detector.ex` - Auto-detection logic
- **Supported Formats**:
  - JSON: `lib/kyozo/lang/universal_parser/formats/json.ex`
  - YAML: `lib/kyozo/lang/universal_parser/formats/yaml.ex`
  - Markdown: `lib/kyozo/lang/universal_parser/formats/markdown.ex`

### Native Performance Layer (Rust NIFs)
- **FSScanner**: `lib/lang/native/fs_scanner.ex` + `native/fs_scanner/` (Rust crate)
- **Performance Engine**: `lib/lang/native/perf_engine.ex` + `native/perf_engine/` (Rust)
- **Tree Parser**: `lib/lang/native/tree_parser.ex` + tree-sitter integration
- **Graph Reasoner**: `lib/lang/graph_reasoner.ex` + `native/graph_reasoner/` (Rust)

### Workspace Management
- **Workspace Resource**: `lib/lang/workspace/workspace.ex` - Ash resource for workspaces
- **Workspace Store**: `lib/lang/workspace/store.ex` - Redis-backed ephemeral state
- **Workspace Service**: `lib/lang/workspace/service.ex` - High-level operations

### Analysis Engine
- **Analysis Engine**: `lib/lang/text_intelligence/analysis_engine.ex` - Core analysis
- **Analysis Resources**: `lib/lang/analysis/` - Ash resources for analysis data
- **Background Workers**: `lib/lang/workers/` - Oban job processing

### MCP Integration
- **MCP Broker**: `lib/lang/mcp/broker.ex` - Secure MCP connection broker
- **MCP Security**: `lib/lang/mcp/security.ex` - Security validation
- **MCP Stream Bridge**: `lib/lang/mcp/stream_bridge.ex` - Real-time streaming
- **Server Configs**: `lib/lang/mcp/resources/server_config.ex` - MCP server definitions

### Configuration & Routing
- **Router**: `lib/lang_web/router.ex` - Phoenix web routes
- **Endpoint**: `lib/lang_web/endpoint.ex` - Phoenix endpoint config
- **Socket**: `lib/lang_web/channels/lsp_socket.ex` - WebSocket authentication

---

## AI Agent Workflows

### Typical AI Agent Session Flow

1. **Initialize Connection**
   ```json
   rpc.initialize → Get capabilities
   lang.workspace.create → Initialize context
   ```

2. **Explore Codebase**
   ```json
   lang.fs.scan → Get project structure
   lang.fs.search → Find relevant files
   textDocument/documentSymbol → Get file structure
   ```

3. **Analyze Content**
   ```json
   lang.analyze.document → Extract intelligence
   lang.parse.structure → Get hierarchical data
   textDocument/hover → Get contextual info
   ```

4. **Navigate and Reference**
   ```json
   textDocument/definition → Follow definitions
   textDocument/references → Find usages
   workspace/symbol → Project-wide search
   ```

5. **Generate Insights**
   ```json
   lang.semantic.diff → Compare versions
   lang.graph.build → Build relationships
   lang.results.get → Retrieve analysis
   ```

### Performance Requirements

| Operation | Target Latency | Max Memory | Notes |
|-----------|---------------|------------|-------|
| `rpc.initialize` | < 100ms | 10MB | Fast startup |
| `lang.fs.scan` | < 2s | 50MB | Large projects |
| `textDocument/completion` | < 50ms | 20MB | Real-time response |
| `lang.analyze.document` | < 1s | 100MB | Complex analysis |
| `textDocument/publishDiagnostics` | < 200ms | 30MB | Quick feedback |

### Error Codes

| Code | Name | Description | When to Use |
|------|------|-------------|-------------|
| -32600 | InvalidRequest | Invalid JSON-RPC | Malformed request |
| -32601 | MethodNotFound | Method not implemented | Unsupported method |
| -32602 | InvalidParams | Invalid parameters | Parameter validation |
| -32603 | InternalError | Server internal error | Unexpected failures |
| -32001 | RateLimited | Rate limit exceeded | Too many requests |
| -32002 | FileNotFound | File doesn't exist | File operations |
| -32003 | ParseError | Failed to parse content | Format issues |
| -32004 | AnalysisError | Analysis failed | Processing errors |
| -32005 | WorkspaceError | Workspace operation failed | Context issues |

### Configuration Options

```json
{
  "lang": {
    "analysis": {
      "enableRealTime": true,
      "maxFileSize": "10MB",
      "excludePatterns": ["node_modules/**", ".git/**"]
    },
    "filesystem": {
      "watchFiles": true,
      "maxDepth": 10,
      "followSymlinks": false
    },
    "performance": {
      "enableCaching": true,
      "parallelWorkers": 4,
      "memoryLimit": "1GB"
    }
  }
}
```

## Implementation Priority

### Phase 1: Core LSP (Essential for any LSP client)
- `initialize`, `shutdown`, `exit`
- `textDocument/didOpen`, `didChange`, `didClose`
- `textDocument/publishDiagnostics`
- `textDocument/completion`, `hover`

### Phase 2: Navigation & Analysis
- `textDocument/definition`, `references`
- `textDocument/documentSymbol`
- `workspace/symbol`
- `lang.analyze.document`

### Phase 3: Advanced Features
- `textDocument/codeAction`, `rename`
- `lang.semantic.diff`
- `lang.graph.build`, `query`
- Streaming operations

### Phase 4: AI-Specific Extensions
- Advanced MCP integration
- Real-time collaborative analysis
- Custom intelligence plugins
- Performance optimization

## Development Frontend Integration

### Registry Access Points
For building a frontend to develop the LSP model, these modules provide programmatic access:

```elixir
# Get all supported formats and their capabilities
formats = Kyozo.Lang.UniversalParser.supported_formats()

# Get parser registry information
parser_info = Lang.TextIntelligence.ParserRegistry.list_all_parsers()

# Get LSP server capabilities
capabilities = Lang.LSP.Server.get_server_capabilities()

# Query workspace information
workspaces = Lang.Workspace.Workspace.read_all()

# Get analysis results
results = Lang.Analysis.AnalyzedFile.read_all()
```

### Method Registration Pattern
New LSP methods should be added to:
1. `lib/lang/rpc/router.ex` - Add dispatch handler
2. `lib/lang/lsp/server.ex` - Add to capabilities list
3. `lib/lang_web/channels/lsp_channel.ex` - Handle WebSocket routing
4. Add tests to `test/lang_web/lsp_*_test.exs`

### Frontend Development Notes
- All LSP methods return JSON-LD wrapped responses via `Lang.RPC.JsonLD.wrap/1`
- Rate limiting enforced via `Lang.Security.RedisLimiter.allow?/2`
- Usage tracking via `Lang.Events.track_event/1`
- Billing limits checked via `Lang.Billing.Service.can_make_request?/1`

This reference serves as the complete specification for implementing a production-ready LSP server that serves both traditional IDE clients and AI agents with comprehensive text intelligence capabilities.
