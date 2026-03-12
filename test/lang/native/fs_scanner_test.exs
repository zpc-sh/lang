defmodule Lang.Native.FSScannerTest do
  use ExUnit.Case, async: true

  alias Lang.Native.FSScanner
  alias Lang.Native.FSScanner.{FileNode, SearchResult, CodeMatch, ScanStats}

  @moduletag :integration

  describe "scan_directory/3" do
    test "scans current directory successfully" do
      {:ok, {tree, stats}} = FSScanner.scan_directory(".", 3, false)

      assert %FileNode{} = tree
      assert tree.node_type == :directory
      assert tree.name != ""
      assert is_list(tree.children)

      assert %ScanStats{} = stats
      assert stats.total_files > 0
      assert stats.total_directories > 0
      assert stats.scan_duration_ms > 0
      assert is_map(stats.files_by_extension)
    end

    test "respects max depth parameter" do
      {:ok, {tree, _stats}} = FSScanner.scan_directory(".", 1, false)

      # At depth 1, children should not have their own children
      if tree.children do
        Enum.each(tree.children, fn child ->
          if child.node_type == :directory do
            # Directory children at max depth should have no children
            assert is_nil(child.children) or child.children == []
          end
        end)
      end
    end

    test "handles hidden files parameter" do
      {:ok, {tree_no_hidden, _}} = FSScanner.scan_directory(".", 2, false)
      {:ok, {tree_with_hidden, _}} = FSScanner.scan_directory(".", 2, true)

      # With hidden files should have same or more items
      no_hidden_count = count_total_nodes(tree_no_hidden)
      with_hidden_count = count_total_nodes(tree_with_hidden)

      assert with_hidden_count >= no_hidden_count
    end

    test "returns error for non-existent path" do
      assert {:error, "path_not_found"} = FSScanner.scan_directory("/non/existent/path", 5, false)
    end

    test "handles empty directories" do
      temp_dir = System.tmp_dir!() |> Path.join("empty_test_dir")
      File.mkdir_p!(temp_dir)

      try do
        {:ok, {tree, stats}} = FSScanner.scan_directory(temp_dir, 5, false)

        assert tree.node_type == :directory
        assert tree.children == [] or is_nil(tree.children)
        assert stats.total_files == 0
        # The directory itself
        assert stats.total_directories == 1
      after
        File.rm_rf(temp_dir)
      end
    end
  end

  describe "search_content/5" do
    setup do
      # Create test files
      temp_dir = System.tmp_dir!() |> Path.join("search_test")
      File.mkdir_p!(temp_dir)

      test_files = [
        {"test.txt", "Hello world\nTODO: fix this\nfunction test() {}"},
        {"app.js", "function main() {\n  console.log('Hello');\n  // FIXME: optimize\n}"},
        {"lib.ex",
         "defmodule Test do\n  def hello do\n    # TODO: implement\n    :ok\n  end\nend"}
      ]

      Enum.each(test_files, fn {filename, content} ->
        File.write!(Path.join(temp_dir, filename), content)
      end)

      on_exit(fn ->
        File.rm_rf(temp_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "finds pattern matches with context", %{temp_dir: temp_dir} do
      results = FSScanner.search_content(temp_dir, "TODO|FIXME", 10, 1, false)

      assert is_list(results)
      # Should find TODO and FIXME
      assert length(results) >= 2

      Enum.each(results, fn result ->
        assert %SearchResult{} = result
        assert String.contains?(result.path, temp_dir)
        assert result.line_number > 0

        assert String.contains?(result.line_text, "TODO") or
                 String.contains?(result.line_text, "FIXME")

        assert is_list(result.context_before)
        assert is_list(result.context_after)
      end)
    end

    test "respects max results parameter", %{temp_dir: temp_dir} do
      # Create more files to test limit
      1..10
      |> Enum.each(fn i ->
        File.write!(Path.join(temp_dir, "file#{i}.txt"), "TODO: task #{i}")
      end)

      results = FSScanner.search_content(temp_dir, "TODO", 3, 0, false)

      assert length(results) <= 3
    end

    test "handles case sensitivity", %{temp_dir: temp_dir} do
      File.write!(Path.join(temp_dir, "case_test.txt"), "TODO: uppercase\ntodo: lowercase")

      # Case insensitive (default)
      results_insensitive = FSScanner.search_content(temp_dir, "todo", 10, 0, false)

      # Case sensitive
      results_sensitive = FSScanner.search_content(temp_dir, "todo", 10, 0, true)

      assert length(results_insensitive) >= length(results_sensitive)
    end

    test "returns empty list for no matches", %{temp_dir: temp_dir} do
      results = FSScanner.search_content(temp_dir, "NONEXISTENT_PATTERN_12345", 10, 0, false)

      assert results == []
    end
  end

  describe "search_code_patterns/4" do
    setup do
      temp_dir = System.tmp_dir!() |> Path.join("code_search_test")
      File.mkdir_p!(temp_dir)

      # Create Rust test file
      rust_content = """
      fn main() {
          println!("Hello, world!");
      }

      fn helper_function() {
          // Helper code
      }

      struct Config {
          name: String,
      }
      """

      File.write!(Path.join(temp_dir, "test.rs"), rust_content)

      # Create JavaScript test file
      js_content = """
      function main() {
          console.log("Hello");
      }

      class Application {
          constructor() {}
      }
      """

      File.write!(Path.join(temp_dir, "test.js"), js_content)

      on_exit(fn ->
        File.rm_rf(temp_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "finds Rust function definitions", %{temp_dir: temp_dir} do
      query = "(function_item name: (identifier) @function)"
      results = FSScanner.search_code_patterns(temp_dir, "rust", query, 10)

      assert is_list(results)
      # main and helper_function
      assert length(results) >= 2

      function_names = Enum.map(results, & &1.matched_text)
      assert "main" in function_names
      assert "helper_function" in function_names

      Enum.each(results, fn match ->
        assert %CodeMatch{} = match
        assert String.ends_with?(match.path, ".rs")
        assert match.start_line > 0
        assert match.capture_name == "function"
      end)
    end

    test "finds JavaScript function definitions", %{temp_dir: temp_dir} do
      query = "(function_declaration name: (identifier) @function)"
      results = FSScanner.search_code_patterns(temp_dir, "javascript", query, 10)

      assert is_list(results)
      assert length(results) >= 1

      main_function = Enum.find(results, &(&1.matched_text == "main"))
      assert main_function != nil
      assert String.ends_with?(main_function.path, ".js")
    end

    test "returns error for unsupported language", %{temp_dir: temp_dir} do
      query = "(function_definition) @function"

      assert {:error, reason} =
               FSScanner.search_code_patterns(temp_dir, "unsupported_lang", query, 10)

      assert String.contains?(reason, "unsupported_language")
    end

    test "handles invalid query syntax", %{temp_dir: temp_dir} do
      invalid_query = "invalid query syntax"

      assert {:error, reason} =
               FSScanner.search_code_patterns(temp_dir, "rust", invalid_query, 10)

      assert String.contains?(reason, "query_error")
    end
  end

  describe "get_file_preview/2" do
    setup do
      temp_file = System.tmp_dir!() |> Path.join("preview_test.txt")

      content = """
      Line 1
      Line 2
      Line 3
      Line 4
      Line 5
      """

      File.write!(temp_file, content)

      on_exit(fn ->
        File.rm(temp_file)
      end)

      {:ok, temp_file: temp_file}
    end

    test "returns file preview with specified line count", %{temp_file: temp_file} do
      lines = FSScanner.get_file_preview(temp_file, 3)

      assert is_list(lines)
      assert length(lines) == 3
      assert Enum.at(lines, 0) == "Line 1"
      assert Enum.at(lines, 1) == "Line 2"
      assert Enum.at(lines, 2) == "Line 3"
    end

    test "handles files shorter than max_lines", %{temp_file: temp_file} do
      lines = FSScanner.get_file_preview(temp_file, 100)

      assert is_list(lines)
      # File only has 5 lines
      assert length(lines) == 5
    end

    test "returns error for non-existent file" do
      assert {:error, "read_error"} = FSScanner.get_file_preview("/non/existent/file.txt", 10)
    end
  end

  describe "high-level wrapper functions" do
    test "FSScanner.scan/2 wrapper works correctly" do
      {:ok, result} = FSScanner.scan(".", max_depth: 2)

      assert Map.has_key?(result, :tree)
      assert Map.has_key?(result, :stats)
      assert %FileNode{} = result.tree
      assert %ScanStats{} = result.stats
    end

    test "FSScanner.search/3 wrapper works correctly" do
      # Create a temporary file to search
      temp_file = System.tmp_dir!() |> Path.join("search_wrapper_test.txt")
      File.write!(temp_file, "Hello world\nTEST pattern here")

      try do
        temp_dir = Path.dirname(temp_file)
        {:ok, results} = FSScanner.search(temp_dir, "TEST", max_results: 5)

        assert is_list(results)
        assert length(results) > 0
      after
        File.rm(temp_file)
      end
    end
  end

  describe "performance characteristics" do
    @tag :performance
    test "scan performance is reasonable" do
      {time_microseconds, {:ok, {_tree, stats}}} =
        :timer.tc(fn ->
          FSScanner.scan_directory(".", 5, false)
        end)

      time_seconds = time_microseconds / 1_000_000
      files_per_second = stats.total_files / time_seconds

      # Should process at least 100 files per second (very conservative)
      assert files_per_second > 100

      # Should complete in reasonable time (less than 10 seconds for moderate directories)
      assert time_seconds < 10.0
    end

    @tag :performance
    test "search performance is reasonable" do
      {time_microseconds, results} =
        :timer.tc(fn ->
          FSScanner.search_content(".", "test|function|def", 100, 0, false)
        end)

      time_seconds = time_microseconds / 1_000_000

      # Search should complete in reasonable time
      assert time_seconds < 5.0

      # Should find some results (assuming current directory has code)
      assert is_list(results)
    end
  end

  describe "integration with Elixir wrapper" do
    test "Lang.Native.FSScanner module loads correctly" do
      # Test that the module is available
      assert function_exported?(Lang.Native.FSScanner, :scan, 2)
      assert function_exported?(Lang.Native.FSScanner, :search, 3)
      assert function_exported?(Lang.Native.FSScanner, :search_code, 4)
    end

    test "common_queries/0 returns expected patterns" do
      queries = FSScanner.common_queries()

      assert is_map(queries)
      assert Map.has_key?(queries, :todos)
      assert Map.has_key?(queries, :functions)
      assert Map.has_key?(queries, :imports)

      # Verify patterns are strings
      assert is_binary(queries.todos)
      assert String.contains?(queries.todos, "TODO")
    end

    test "tree_sitter_queries/0 returns structured queries" do
      queries = FSScanner.tree_sitter_queries()

      assert is_map(queries)
      assert Map.has_key?(queries, :rust)
      assert Map.has_key?(queries, :javascript)

      rust_queries = queries.rust
      assert is_map(rust_queries)
      assert Map.has_key?(rust_queries, :functions)
      assert Map.has_key?(rust_queries, :structs)
    end
  end

  # Helper functions

  defp count_total_nodes(%FileNode{children: nil}), do: 1
  defp count_total_nodes(%FileNode{children: []}), do: 1

  defp count_total_nodes(%FileNode{children: children}) when is_list(children) do
    1 + Enum.sum(Enum.map(children, &count_total_nodes/1))
  end

  defp count_total_nodes(_), do: 1
end
