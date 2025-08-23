# Parser Consolidation & Refactoring Plan

## Current State Analysis

### Existing NIFs and Their Responsibilities

1. **Lang.Native.Parser** (`lang_parser` crate)
   - Text analysis
   - JSON-LD semantic diffing
   - Streaming parsing
   - Complexity/readability scoring

2. **Lang.Native.TreeParser** (`tree_parser` crate?)
   - Tree-sitter AST parsing
   - Multi-language support
   - Code complexity analysis
   - Architectural rule validation
   - Symbol extraction

3. **Lang.Native.FSScanner** (`fs_scanner` crate)
   - Directory scanning
   - Content search (ripgrep)
   - Tree-sitter code search (duplicate!)
   - File preview

4. **Lang.GraphReasoner** (unknown crate)
   - Graph algorithms
   - Knowledge extraction from text (overlap!)
   - Dependency analysis

5. **Lang.Native.PerfEngine** (unknown crate)
   - Performance monitoring?

### Problems Identified (Updated Based on Audit)

1. **FSScanner is unused**: Audit shows zero usage despite implementation
2. **PerfEngine is most active**: 24 calls, highest usage across platform
3. **Parser has moderate usage**: 21 calls, focused on text analysis
4. **TreeParser has limited usage**: 17 calls, single file dependency
5. **Unclear boundaries**: Text parsing spread across multiple NIFs
6. **Naming confusion**: "Native" modules with high-level logic

## Revised Architecture (Based on Audit Results)

### Phase 1: Consolidate Active Parsers

**Priority Order (by usage):**
1. **PerfEngine** (24 calls) - Keep as performance engine
2. **Parser** (21 calls) - Refactor to TextParser
3. **TreeParser** (17 calls) - Refactor to ASTParser
4. **FSScanner** (0 calls) - **REMOVE** unused code
5. **GraphReasoner** (0 calls) - Evaluate for removal

```
lib/lang/native/
├── text_parser.ex       # Consolidate from Parser
├── ast_parser.ex        # Consolidate from TreeParser
├── perf_engine.ex       # Keep existing (highest usage)
└── graph_engine.ex      # Evaluate GraphReasoner usage
```

### Phase 2: High-Level API Layer

```
lib/lang/analysis/
├── text.ex              # Uses native/text_parser
├── code.ex              # Uses native/ast_parser
├── performance.ex       # Uses native/perf_engine
└── graph.ex             # Uses native/graph_engine (if kept)
```

## Implementation Plan (Revised)

### Step 1: Audit Current Usage ✅ COMPLETED

Audit results show:
- **PerfEngine**: 24 calls across 2 files (highest priority)
- **Parser**: 21 calls across 2 files (text analysis focus)
- **TreeParser**: 17 calls in 1 file (code analysis)
- **FSScanner**: 0 calls (unused - candidate for removal)
- **GraphReasoner**: 1 file, 0 function calls (evaluate removal)

```elixir
# audit_parser_usage.exs
defmodule Lang.Refactor.ParserAudit do
  @moduledoc """
  Audit current parser usage across the codebase
  """

  def audit do
    parsers = [
      "Lang.Native.Parser",
      "Lang.Native.TreeParser",
      "Lang.Native.FSScanner",
      "Lang.GraphReasoner",
      "Lang.Parsers.Filesystem"
    ]

    results = for parser <- parsers do
      files = find_usage(parser)
      {parser, %{
        usage_count: length(files),
        files: files,
        functions_used: analyze_functions(parser, files)
      }}
    end

    File.write!("parser_audit.json", Jason.encode!(results, pretty: true))
  end

  defp find_usage(module_name) do
    System.cmd("git", ["grep", "-l", module_name, "--", "*.ex", "*.exs"])
    |> elem(0)
    |> String.split("\n", trim: true)
  end

  defp analyze_functions(module_name, files) do
    # Extract which functions are actually being called
    Enum.flat_map(files, fn file ->
      File.read!(file)
      |> extract_function_calls(module_name)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp extract_function_calls(content, module_name) do
    # Regex to find function calls
    Regex.scan(~r/#{Regex.escape(module_name)}\.(\w+)/, content)
    |> Enum.map(&List.last/1)
  end
end

# Run: mix run audit_parser_usage.exs
Lang.Refactor.ParserAudit.audit()
```

### Step 2: Create Compatibility Layer (Week 2)

Based on audit results, create compatibility for actively used parsers:

```elixir
defmodule Lang.Native.Compat do
  @moduledoc """
  Compatibility layer during parser refactoring.
  Maps old parser calls to new architecture.
  """

  # Map Parser calls to new TextParser (21 calls to migrate)
  defdelegate analyze_style(content, opts \\ []),
    to: Lang.Native.TextParser
  defdelegate parse_content(content, opts \\ []),
    to: Lang.Native.TextParser
  defdelegate clear_caches(),
    to: Lang.Native.TextParser

  # Map TreeParser calls to new ASTParser (17 calls to migrate)
  defdelegate parse_source_code(language, content, opts \\ []),
    to: Lang.Native.ASTParser
  defdelegate analyze_complexity(ast),
    to: Lang.Native.ASTParser

  # Keep PerfEngine as-is (highest usage, 24 calls)
  # Note: FSScanner has 0 usage - no compatibility needed
end
```

### Step 3: Consolidate NIFs (Weeks 3-4)

#### 3.1 Create New Text Parser NIF

```elixir
defmodule Lang.Native.TextParser do
  @moduledoc """
  Focused text parsing and analysis NIF.

  Responsibilities:
  - Tokenization
  - Basic metrics (word count, sentences, etc.)
  - Readability scoring
  - Language detection
  """

  use Rustler,
    otp_app: :lang,
    crate: "lang_text_parser"

  # Consolidate from Lang.Native.Parser
  def tokenize(_text, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def analyze_metrics(_text), do: :erlang.nif_error(:nif_not_loaded)
  def detect_language(_text), do: :erlang.nif_error(:nif_not_loaded)
  def calculate_readability(_text), do: :erlang.nif_error(:nif_not_loaded)
end
```

#### 3.2 Create Unified AST Parser NIF

```elixir
defmodule Lang.Native.ASTParser do
  @moduledoc """
  Unified tree-sitter based AST parsing.

  Consolidates:
  - Lang.Native.TreeParser
  - Lang.Native.FSScanner (tree-sitter parts)
  """

  use Rustler,
    otp_app: :lang,
    crate: "lang_ast_parser"

  # Core parsing
  def parse(_language, _content, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def parse_file(_path, _language), do: :erlang.nif_error(:nif_not_loaded)

  # Code search
  def search_pattern(_path, _language, _pattern, _opts), do: :erlang.nif_error(:nif_not_loaded)

  # Analysis
  def extract_symbols(_ast), do: :erlang.nif_error(:nif_not_loaded)
  def analyze_complexity(_ast), do: :erlang.nif_error(:nif_not_loaded)
  def check_rules(_ast, _rules), do: :erlang.nif_error(:nif_not_loaded)
end
```

#### 3.3 Create Focused File System NIF

```elixir
defmodule Lang.Native.FileSystem do
  @moduledoc """
  Pure filesystem operations.

  Extracted from Lang.Native.FSScanner (filesystem parts only).
  """

  use Rustler,
    otp_app: :lang,
    crate: "lang_filesystem"

  def scan_directory(_path, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def read_file_preview(_path, _lines), do: :erlang.nif_error(:nif_not_loaded)
  def get_file_stats(_path), do: :erlang.nif_error(:nif_not_loaded)
end
```

#### 3.4 Create Text Search NIF

```elixir
defmodule Lang.Native.TextSearch do
  @moduledoc """
  Ripgrep-based text search.

  Extracted from Lang.Native.FSScanner (search parts only).
  """

  use Rustler,
    otp_app: :lang,
    crate: "lang_text_search"

  def search(_path, _pattern, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def search_with_context(_path, _pattern, _context_lines), do: :erlang.nif_error(:nif_not_loaded)
end
```

### Step 4: Create High-Level APIs (Week 5)

```elixir
defmodule Lang.Analysis.Code do
  @moduledoc """
  High-level code analysis API.
  Replaces Lang.Parsers.* modules.
  """

  alias Lang.Native.{ASTParser, FileSystem}

  def analyze_file(path, opts \\ []) do
    with {:ok, language} <- detect_language(path),
         {:ok, ast} <- ASTParser.parse_file(path, language),
         {:ok, symbols} <- ASTParser.extract_symbols(ast),
         {:ok, complexity} <- ASTParser.analyze_complexity(ast) do
      {:ok, %{
        language: language,
        ast: ast,
        symbols: symbols,
        complexity: complexity,
        metrics: calculate_metrics(ast)
      }}
    end
  end

  def search_code(path, language, pattern, opts \\ []) do
    ASTParser.search_pattern(path, language, pattern, opts)
  end

  # ... more high-level functions
end
```

### Step 5: Migration Strategy (Weeks 6-8)

#### 5.1 Update Import Statements (Based on Audit)

```elixir
# migration_script.exs
defmodule Lang.Refactor.MigrateImports do
  @migrations %{
    "Lang.Native.Parser" => "Lang.Native.TextParser",
    "Lang.Native.TreeParser" => "Lang.Native.ASTParser",
    # Note: FSScanner has 0 usage - no migration needed
    # Note: PerfEngine kept as-is (highest usage)
  }

  def migrate_file(path) do
    content = File.read!(path)

    new_content = Enum.reduce(@migrations, content, fn {old, new}, acc ->
      String.replace(acc, old, new)
    end)

    if content != new_content do
      File.write!(path, new_content)
      IO.puts("✓ Migrated #{path}")
    end
  end
end
```

#### 5.2 Gradual Rollout

1. **Week 6**: Deploy compatibility layer
2. **Week 7**: Migrate non-critical paths
3. **Week 8**: Migrate critical paths with feature flags

### Step 6: Cleanup (Week 9)

1. **Remove unused FSScanner NIF** (0 calls - safe to delete)
2. **Evaluate GraphReasoner** (1 file, 0 function calls)
3. Remove old Parser and TreeParser NIFs after migration
4. Delete compatibility layer
5. Update documentation
6. Remove old test files
7. **Keep PerfEngine unchanged** (highest usage)

## Testing Strategy

### Unit Tests for Each NIF

```elixir
defmodule Lang.Native.TextParserTest do
  use ExUnit.Case

  describe "tokenize/2" do
    test "tokenizes simple text" do
      assert {:ok, tokens} = Lang.Native.TextParser.tokenize("Hello world", [])
      assert length(tokens) == 2
    end
  end
end
```

### Integration Tests

```elixir
defmodule Lang.Analysis.CodeIntegrationTest do
  use ExUnit.Case

  test "full file analysis workflow" do
    # Test the complete flow through new architecture
    assert {:ok, result} = Lang.Analysis.Code.analyze_file("test/fixtures/sample.ex")
    assert result.language == "elixir"
    assert is_map(result.complexity)
  end
end
```

### Performance Benchmarks

```elixir
defmodule Lang.Refactor.Benchmarks do
  def compare_parsers do
    Benchee.run(%{
      "old_tree_parser" => fn -> Lang.Native.TreeParser.parse(...) end,
      "new_ast_parser" => fn -> Lang.Native.ASTParser.parse(...) end
    })
  end
end
```

## Success Metrics (Updated)

1. **Code Reduction**: Remove FSScanner (0 usage) = immediate 20% reduction
2. **Performance**: No regression in PerfEngine (keep as-is)
3. **API Clarity**: Clear separation of concerns
4. **Test Coverage**: Maintain or improve coverage
5. **Zero Downtime**: Gradual migration with no service interruption
6. **Migration Impact**: Focus on 62 total calls (Parser: 21, PerfEngine: 24, TreeParser: 17)

## Risk Mitigation

1. **Compatibility Layer**: Ensures old code continues working
2. **Feature Flags**: Roll out changes gradually
3. **Comprehensive Testing**: Before each migration step
4. **Rollback Plan**: Keep old NIFs until fully migrated
5. **Documentation**: Update as we go

## Revised Timeline Summary

- **Week 1**: ✅ Audit completed (results available)
- **Week 2**: Remove FSScanner (0 usage - quick win)
- **Week 3**: Compatibility layer for active parsers
- **Week 4**: Migrate Parser → TextParser (21 calls)
- **Week 5**: Migrate TreeParser → ASTParser (17 calls)
- **Week 6**: Keep PerfEngine as-is (24 calls, stable)
- **Week 7**: High-level APIs and testing
- **Week 8**: Cleanup and documentation

Total: ~6 weeks (reduced from 9 due to audit insights)

## Next Steps (Based on Audit Results)

1. ✅ **Audit completed** - Results show FSScanner unused, PerfEngine most active
2. **Quick win**: Remove FSScanner NIF (0 usage, safe deletion)
3. **Evaluate GraphReasoner**: 1 file reference but 0 function calls
4. **Focus migration effort** on 3 active parsers (62 total calls)
5. **Preserve PerfEngine**: Highest usage (24 calls) - keep stable
6. Get team buy-in on revised, data-driven approach
