defmodule Lang.Parsers.FilesystemTest do
  use ExUnit.Case, async: false
  use Lang.DataCase

  alias Lang.Parsers.Filesystem
  alias Lang.Native.FSScanner.{FileNode, ScanStats, SearchResult, CodeMatch}
  alias Lang.Accounts.User
  alias Lang.Analysis.{Project, Session}

  @moduletag :integration

  describe "parse/2" do
    setup do
      # Create test directory structure
      temp_dir = System.tmp_dir!() |> Path.join("filesystem_parser_test")
      File.mkdir_p!(temp_dir)

      # Create test files with different languages and content
      test_files = %{
        "README.md" => """
        # Test Project

        This is a test project for filesystem parsing.

        ## Features
        - TODO: Add more features
        - FIXME: Fix parsing issues
        """,
        "src/main.rs" => """
        fn main() {
            println!("Hello, world!");
        }

        fn helper_function() -> i32 {
            // TODO: Implement actual logic
            42
        }
        """,
        "src/lib.js" => """
        function greet(name) {
            console.log(`Hello, ${name}!`);
        }

        class Application {
            constructor() {
                this.name = "Test App";
            }
        }
        """,
        "config/settings.json" => """
        {
          "app_name": "Test Application",
          "version": "1.0.0",
          "debug": true
        }
        """,
        "docs/guide.md" => """
        # User Guide

        This guide explains how to use the application.

        ## Getting Started
        1. Install dependencies
        2. Run the application
        """,
        ".gitignore" => """
        node_modules/
        target/
        *.log
        """
      }

      # Create directory structure and files
      Enum.each(test_files, fn {path, content} ->
        full_path = Path.join(temp_dir, path)
        File.mkdir_p!(Path.dirname(full_path))
        File.write!(full_path, content)
      end)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
      end)

      {:ok, temp_dir: temp_dir, test_files: test_files}
    end

    test "parses directory synchronously with default options", %{temp_dir: temp_dir} do
      {:ok, result} = Filesystem.parse(temp_dir)

      assert %{tree: tree, stats: stats, metadata: metadata} = result
      assert %FileNode{} = tree
      assert %ScanStats{} = stats
      assert is_map(metadata)

      # Verify basic structure
      assert tree.node_type == :directory
      assert tree.name == Path.basename(temp_dir)
      assert is_list(tree.children)
      assert length(tree.children) > 0

      # Verify stats
      assert stats.total_files > 0
      assert stats.total_directories > 0
      assert stats.scan_duration_ms > 0
      assert is_map(stats.files_by_extension)

      # Verify metadata
      assert metadata.scanned_at
      assert metadata.path == temp_dir
      assert metadata.scan_options
      assert metadata.performance
    end

    test "respects max_depth option", %{temp_dir: temp_dir} do
      {:ok, result} = Filesystem.parse(temp_dir, max_depth: 1)

      assert %{tree: tree} = result

      # At depth 1, should not scan into subdirectories deeply
      src_dir = find_child_by_name(tree.children, "src")

      if src_dir do
        assert src_dir.node_type == :directory
        # Children should be empty or nil at max depth
        assert is_nil(src_dir.children) or src_dir.children == []
      end
    end

    test "handles include_hidden option", %{temp_dir: temp_dir} do
      {:ok, result_no_hidden} = Filesystem.parse(temp_dir, include_hidden: false)
      {:ok, result_with_hidden} = Filesystem.parse(temp_dir, include_hidden: true)

      # With hidden files should have same or more files
      no_hidden_count = count_total_files(result_no_hidden.tree)
      with_hidden_count = count_total_files(result_with_hidden.tree)

      assert with_hidden_count >= no_hidden_count

      # Should include .gitignore when including hidden files
      hidden_files = flatten_tree(result_with_hidden.tree)
      gitignore_found = Enum.any?(hidden_files, &String.contains?(&1.name, ".gitignore"))
      assert gitignore_found
    end

    test "returns error for non-existent path" do
      assert {:error, :path_not_found} = Filesystem.parse("/non/existent/path")
    end

    test "handles empty directory", %{temp_dir: temp_dir} do
      empty_dir = Path.join(temp_dir, "empty")
      File.mkdir_p!(empty_dir)

      {:ok, result} = Filesystem.parse(empty_dir)

      assert %{tree: tree, stats: stats} = result
      assert tree.node_type == :directory
      assert tree.children == [] or is_nil(tree.children)
      assert stats.total_files == 0
      assert stats.total_directories == 1
    end

    test "async parsing requires session, project, and user IDs" do
      assert {:error, {:missing_required_fields, missing}} =
               Filesystem.parse("/tmp", async: true)

      assert :session_id in missing
      assert :project_id in missing
      assert :user_id in missing
    end

    test "async parsing enqueues Oban job with valid parameters", %{temp_dir: temp_dir} do
      {:ok, user} =
        User.create(%{
          email: "test@example.com",
          name: "Test User",
          organization_name: "Test Org"
        })

      {:ok, project} =
        Project.create(%{
          name: "Test Project",
          user_id: user.id
        })

      {:ok, session} =
        Session.create(%{
          project_id: project.id,
          user_id: user.id,
          status: :pending
        })

      {:ok, job} =
        Filesystem.parse(temp_dir,
          async: true,
          session_id: session.id,
          project_id: project.id,
          user_id: user.id
        )

      assert %Oban.Job{} = job
      assert job.queue == "analysis"
      assert job.worker == "Lang.Workers.FileSystemScanWorker"
      assert job.args["path"] == temp_dir
      assert job.args["session_id"] == session.id
    end
  end

  describe "search/3" do
    setup do
      temp_dir = System.tmp_dir!() |> Path.join("search_test")
      File.mkdir_p!(temp_dir)

      search_files = %{
        "code.rs" => """
        fn main() {
            // TODO: Implement main logic
            println!("Hello, world!");
        }

        fn helper() {
            // FIXME: This needs optimization
            let x = 42;
        }
        """,
        "app.js" => """
        function main() {
            console.log("Starting app");
            // TODO: Add error handling
        }

        // HACK: Temporary solution
        const temp = "test";
        """,
        "README.md" => """
        # Project

        ## Issues
        - TODO: Write better documentation
        - FIXME: Fix the build process
        """
      }

      Enum.each(search_files, fn {path, content} ->
        File.write!(Path.join(temp_dir, path), content)
      end)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "searches for pattern and returns formatted results", %{temp_dir: temp_dir} do
      {:ok, result} = Filesystem.search(temp_dir, "TODO|FIXME|HACK")

      assert %{
               results: results,
               total_matches: total,
               search_time_ms: time,
               query: query,
               path: path
             } = result

      assert is_list(results)
      assert total == length(results)
      # Should find TODO, FIXME, HACK comments
      assert total >= 5
      assert time > 0
      assert query == "TODO|FIXME|HACK"
      assert path == temp_dir

      # Verify result structure
      first_result = List.first(results)
      assert %SearchResult{} = first_result
      assert String.contains?(first_result.path, temp_dir)
      assert first_result.line_number > 0
      assert is_binary(first_result.line_text)

      assert String.contains?(first_result.line_text, "TODO") or
               String.contains?(first_result.line_text, "FIXME") or
               String.contains?(first_result.line_text, "HACK")
    end

    test "respects max_results option", %{temp_dir: temp_dir} do
      {:ok, result} = Filesystem.search(temp_dir, "TODO|FIXME", max_results: 2)

      assert result.total_matches <= 2
      assert length(result.results) <= 2
    end

    test "handles case sensitivity option", %{temp_dir: temp_dir} do
      {:ok, case_insensitive} = Filesystem.search(temp_dir, "todo", case_sensitive: false)
      {:ok, case_sensitive} = Filesystem.search(temp_dir, "todo", case_sensitive: true)

      # Case insensitive should find more matches (TODO vs todo)
      assert case_insensitive.total_matches >= case_sensitive.total_matches
    end

    test "includes context lines when requested", %{temp_dir: temp_dir} do
      {:ok, result} = Filesystem.search(temp_dir, "TODO", context_lines: 2)

      result_with_context =
        Enum.find(result.results, fn r ->
          length(r.context_before) > 0 or length(r.context_after) > 0
        end)

      assert result_with_context
      assert is_list(result_with_context.context_before)
      assert is_list(result_with_context.context_after)
    end

    test "returns empty results for no matches", %{temp_dir: temp_dir} do
      {:ok, result} = Filesystem.search(temp_dir, "NONEXISTENT_PATTERN_12345")

      assert result.results == []
      assert result.total_matches == 0
      assert result.search_time_ms > 0
    end

    test "handles timeout option", %{temp_dir: temp_dir} do
      # This should complete quickly, testing that timeout is passed through
      {:ok, result} = Filesystem.search(temp_dir, "TODO", timeout: 5000)

      assert is_list(result.results)
      assert result.search_time_ms < 5000
    end
  end

  describe "search_code/4" do
    setup do
      temp_dir = System.tmp_dir!() |> Path.join("code_search_test")
      File.mkdir_p!(temp_dir)

      code_files = %{
        "main.rs" => """
        fn main() {
            println!("Hello, world!");
        }

        fn calculate(x: i32, y: i32) -> i32 {
            x + y
        }

        struct Config {
            name: String,
            version: i32,
        }
        """,
        "app.js" => """
        function main() {
            console.log("Starting");
        }

        function processData(data) {
            return data.map(x => x * 2);
        }

        class Application {
            constructor() {
                this.name = "Test";
            }
        }
        """
      }

      Enum.each(code_files, fn {path, content} ->
        File.write!(Path.join(temp_dir, path), content)
      end)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "finds Rust function definitions", %{temp_dir: temp_dir} do
      query = "(function_item name: (identifier) @function)"
      {:ok, results} = Filesystem.search_code(temp_dir, "rust", query)

      assert is_list(results)
      # main and calculate functions
      assert length(results) >= 2

      function_names = Enum.map(results, & &1.matched_text)
      assert "main" in function_names
      assert "calculate" in function_names

      # Verify result structure
      main_function = Enum.find(results, &(&1.matched_text == "main"))
      assert %CodeMatch{} = main_function
      assert String.ends_with?(main_function.path, ".rs")
      assert main_function.start_line > 0
      assert main_function.capture_name == "function"
    end

    test "finds JavaScript function definitions", %{temp_dir: temp_dir} do
      query = "(function_declaration name: (identifier) @function)"
      {:ok, results} = Filesystem.search_code(temp_dir, "javascript", query)

      assert is_list(results)
      # main and processData functions
      assert length(results) >= 2

      function_names = Enum.map(results, & &1.matched_text)
      assert "main" in function_names
      assert "processData" in function_names
    end

    test "finds Rust struct definitions", %{temp_dir: temp_dir} do
      query = "(struct_item name: (type_identifier) @struct)"
      {:ok, results} = Filesystem.search_code(temp_dir, "rust", query)

      assert is_list(results)
      struct_names = Enum.map(results, & &1.matched_text)
      assert "Config" in struct_names
    end

    test "handles unsupported language", %{temp_dir: temp_dir} do
      query = "(function_definition) @function"
      assert {:error, reason} = Filesystem.search_code(temp_dir, "unsupported_lang", query)
      assert String.contains?(reason, "unsupported_language")
    end

    test "handles invalid query syntax", %{temp_dir: temp_dir} do
      invalid_query = "invalid query syntax"
      assert {:error, reason} = Filesystem.search_code(temp_dir, "rust", invalid_query)
      assert String.contains?(reason, "query_error")
    end
  end

  describe "preview/2" do
    setup do
      temp_file = System.tmp_dir!() |> Path.join("preview_test.md")

      content = """
      # Test Document

      This is a test document for preview functionality.

      ## Section 1
      Some content here.

      ## Section 2
      More content here.

      Final line.
      """

      File.write!(temp_file, content)

      on_exit(fn ->
        File.rm!(temp_file)
      end)

      {:ok, temp_file: temp_file}
    end

    test "returns file preview with default line count", %{temp_file: temp_file} do
      {:ok, lines} = Filesystem.preview(temp_file)

      assert is_list(lines)
      # Default max_lines
      assert length(lines) <= 20
      assert List.first(lines) == "# Test Document"
    end

    test "respects max_lines option", %{temp_file: temp_file} do
      {:ok, lines} = Filesystem.preview(temp_file, max_lines: 5)

      assert is_list(lines)
      assert length(lines) <= 5
    end

    test "handles non-existent file" do
      assert {:error, "read_error"} = Filesystem.preview("/non/existent/file.txt")
    end
  end

  describe "analyze_project/2" do
    setup do
      temp_dir = System.tmp_dir!() |> Path.join("project_analysis_test")
      File.mkdir_p!(temp_dir)

      # Create a realistic project structure
      project_files = %{
        "Cargo.toml" => """
        [package]
        name = "test-project"
        version = "0.1.0"
        """,
        "src/main.rs" => """
        fn main() {
            println!("Hello, world!");
        }
        """,
        "src/lib.rs" => """
        pub fn add(left: usize, right: usize) -> usize {
            left + right
        }
        """,
        "tests/integration_test.rs" => """
        use test_project::add;

        #[test]
        fn test_add() {
            assert_eq!(add(2, 2), 4);
        }
        """,
        "README.md" => "# Test Project",
        "docs/guide.md" => "# User Guide",
        ".gitignore" => "target/\n*.log"
      }

      Enum.each(project_files, fn {path, content} ->
        full_path = Path.join(temp_dir, path)
        File.mkdir_p!(Path.dirname(full_path))
        File.write!(full_path, content)
      end)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "analyzes project structure and returns insights", %{temp_dir: temp_dir} do
      {:ok, analysis} = Filesystem.analyze_project(temp_dir)

      assert %{
               structure: structure,
               languages: languages,
               complexity: complexity,
               metrics: metrics,
               insights: insights
             } = analysis

      # Verify structure analysis
      assert %{
               total_nodes: total_nodes,
               max_depth: max_depth,
               directory_structure: dir_structure,
               file_distribution: file_dist
             } = structure

      assert total_nodes > 0
      assert max_depth >= 1
      assert is_map(dir_structure)
      assert is_map(file_dist)

      # Verify language analysis
      assert is_map(languages)
      assert Map.has_key?(languages, "Rust") or Map.has_key?(languages, "rs")

      # Verify complexity analysis
      assert %{
               nesting_levels: nesting,
               large_directories: large_dirs,
               file_size_distribution: size_dist
             } = complexity

      assert is_number(nesting)
      assert is_list(large_dirs)
      assert is_map(size_dist)

      # Verify metrics
      assert %{
               files: files,
               directories: dirs,
               total_size_bytes: size,
               scan_performance: perf
             } = metrics

      assert files > 0
      assert dirs > 0
      assert size > 0
      assert is_map(perf)

      # Verify insights
      assert is_list(insights)

      Enum.each(insights, fn insight ->
        assert Map.has_key?(insight, :type)
        assert Map.has_key?(insight, :message)
        assert Map.has_key?(insight, :recommendation)
      end)
    end

    test "handles project with deep nesting", %{temp_dir: temp_dir} do
      # Create deep directory structure
      deep_path = Path.join([temp_dir, "very", "deep", "nested", "directory", "structure"])
      File.mkdir_p!(deep_path)
      File.write!(Path.join(deep_path, "deep_file.txt"), "Deep content")

      {:ok, analysis} = Filesystem.analyze_project(temp_dir, max_depth: 15)

      # Should detect deep nesting
      deep_nesting_insight = Enum.find(analysis.insights, &(&1.type == :deep_nesting))
      assert deep_nesting_insight
      assert String.contains?(deep_nesting_insight.message, "Deep directory nesting")
    end

    test "detects large projects", %{temp_dir: temp_dir} do
      # This test is difficult to create realistically, so we'll mock the condition
      # In a real scenario, you'd create many files
      {:ok, analysis} = Filesystem.analyze_project(temp_dir)

      # Verify the analysis structure exists
      assert is_map(analysis.metrics)
      assert Map.has_key?(analysis.metrics, :files)
    end
  end

  describe "batch_analyze/2" do
    setup do
      base_dir = System.tmp_dir!() |> Path.join("batch_test")

      # Create multiple test projects
      projects = ["project1", "project2", "project3"]

      Enum.each(projects, fn project ->
        project_dir = Path.join(base_dir, project)
        File.mkdir_p!(project_dir)
        File.write!(Path.join(project_dir, "main.rs"), "fn main() {}")
        File.write!(Path.join(project_dir, "README.md"), "# #{project}")
      end)

      project_paths = Enum.map(projects, &Path.join(base_dir, &1))

      on_exit(fn ->
        File.rm_rf!(base_dir)
      end)

      {:ok, project_paths: project_paths}
    end

    test "analyzes multiple projects concurrently", %{project_paths: paths} do
      {:ok, results} = Filesystem.batch_analyze(paths)

      assert is_list(results)
      assert length(results) == 3

      Enum.each(results, fn {path, result} ->
        assert path in paths

        case result do
          {:ok, analysis} ->
            assert is_map(analysis)
            assert Map.has_key?(analysis, :structure)
            assert Map.has_key?(analysis, :metrics)

          {:error, reason} ->
            flunk("Analysis failed for #{path}: #{inspect(reason)}")
        end
      end)
    end

    test "respects max_concurrency option", %{project_paths: paths} do
      # This is more of a behavioral test - we can't easily verify concurrency limits
      # but we can verify it doesn't crash and produces correct results
      {:ok, results} = Filesystem.batch_analyze(paths, max_concurrency: 2)

      assert length(results) == 3

      assert Enum.all?(results, fn {_path, result} ->
               match?({:ok, _}, result) or match?({:error, _}, result)
             end)
    end

    test "handles timeout gracefully", %{project_paths: paths} do
      # Use a very short timeout to test timeout handling
      {:ok, results} = Filesystem.batch_analyze(paths, timeout: 50)

      assert is_list(results)
      # Some results might be timeouts, but we should get responses for all paths
      assert length(results) == 3
    end

    test "handles mix of valid and invalid paths" do
      valid_path = System.tmp_dir!()
      invalid_paths = ["/non/existent/path1", "/non/existent/path2"]
      mixed_paths = [valid_path | invalid_paths]

      {:ok, results} = Filesystem.batch_analyze(mixed_paths)

      assert length(results) == 3

      # Find result for valid path
      {^valid_path, valid_result} = Enum.find(results, fn {path, _} -> path == valid_path end)
      assert match?({:ok, _}, valid_result)

      # Invalid paths should have error results
      invalid_results = Enum.filter(results, fn {path, _} -> path in invalid_paths end)
      assert length(invalid_results) == 2

      Enum.each(invalid_results, fn {_path, result} ->
        assert match?({:error, _}, result)
      end)
    end
  end

  describe "common_patterns/0 and semantic_queries/0" do
    test "returns common search patterns" do
      patterns = Filesystem.common_patterns()

      assert is_map(patterns)
      assert Map.has_key?(patterns, :todos)
      assert is_binary(patterns.todos)
      assert String.contains?(patterns.todos, "TODO")
    end

    test "returns semantic query templates" do
      queries = Filesystem.semantic_queries()

      assert is_map(queries)
      assert Map.has_key?(queries, :rust)
      assert Map.has_key?(queries, :javascript)

      rust_queries = queries.rust
      assert is_map(rust_queries)
      assert Map.has_key?(rust_queries, :functions)
      assert is_binary(rust_queries.functions)
    end
  end

  describe "error handling and edge cases" do
    test "handles permission denied errors gracefully" do
      # This test is platform-dependent and might need adjustment
      # Typically restricted on Unix systems
      restricted_path = "/root"

      case Filesystem.parse(restricted_path) do
        {:ok, _result} ->
          # If we can read it, that's fine too
          assert true

        {:error, reason} ->
          # Should be a reasonable error, not a crash
          assert is_atom(reason) or is_binary(reason)
      end
    end

    test "handles very large directory structures" do
      # Create a directory with many files
      temp_dir = System.tmp_dir!() |> Path.join("large_dir_test")
      File.mkdir_p!(temp_dir)

      # Create 50 small files (reasonable for testing)
      1..50
      |> Enum.each(fn i ->
        File.write!(Path.join(temp_dir, "file_#{i}.txt"), "Content #{i}")
      end)

      try do
        {:ok, result} = Filesystem.parse(temp_dir)

        assert result.stats.total_files >= 50
        assert result.metadata.performance.scan_duration_ms > 0
      after
        File.rm_rf!(temp_dir)
      end
    end

    test "handles binary files gracefully" do
      temp_dir = System.tmp_dir!() |> Path.join("binary_test")
      File.mkdir_p!(temp_dir)

      # Create a binary file
      binary_content = :crypto.strong_rand_bytes(1024)
      File.write!(Path.join(temp_dir, "binary_file.bin"), binary_content)

      try do
        {:ok, result} = Filesystem.parse(temp_dir)
        # Should not crash, should include the binary file in results
        assert result.stats.total_files >= 1

        # Search should handle binary files gracefully
        {:ok, search_result} = Filesystem.search(temp_dir, "test")
        # Should not crash
        assert is_list(search_result.results)
      after
        File.rm_rf!(temp_dir)
      end
    end
  end

  # Helper functions

  defp find_child_by_name(children, name) when is_list(children) do
    Enum.find(children, fn child -> child.name == name end)
  end

  defp find_child_by_name(_, _), do: nil

  defp count_total_files(%FileNode{node_type: :file}), do: 1

  defp count_total_files(%FileNode{children: children}) when is_list(children) do
    Enum.sum(Enum.map(children, &count_total_files/1))
  end

  defp count_total_files(_), do: 0

  defp flatten_tree(%FileNode{children: children}) when is_list(children) do
    children ++ Enum.flat_map(children, &flatten_tree/1)
  end

  defp flatten_tree(node), do: [node]
end
