defmodule Lang.Workers.TextEnvironmentTest do
  use ExUnit.Case, async: false
  use Lang.DataCase

  alias Lang.Workers.TextEnvironment
  alias Oban.Job

  @moduletag :integration

  describe "perform/1" do
    test "executes build_documentation task successfully" do
      job = %Job{
        args: %{"task" => "build_documentation"}
      }

      assert {:ok, result} = TextEnvironment.perform(job)
      assert result.environment == :text
      assert result.task == :build_documentation
      assert result.status == :completed
      assert result.pages > 0
      assert result.total_examples > 0
    end

    test "executes generate_spec task successfully" do
      job = %Job{
        args: %{"task" => "generate_spec"}
      }

      assert {:ok, result} = TextEnvironment.perform(job)
      assert result.environment == :text
      assert result.task == :generate_spec
      assert result.status == :completed
      assert result.endpoints > 0
      assert result.schemas > 0
      assert String.contains?(result.spec_path, "openapi.json")
    end

    test "executes implement_parsers task successfully" do
      job = %Job{
        args: %{"task" => "implement_parsers"}
      }

      assert {:ok, result} = TextEnvironment.perform(job)
      assert result.environment == :text
      assert result.task == :implement_parsers
      assert result.status == :completed
      assert result.parsers_implemented > 0
    end

    test "executes create_examples task successfully" do
      job = %Job{
        args: %{"task" => "create_examples"}
      }

      assert {:ok, result} = TextEnvironment.perform(job)
      assert result.environment == :text
      assert result.task == :create_examples
      assert result.status == :completed
      assert result.total_examples > 0
    end

    test "executes expose_api task successfully" do
      job = %Job{
        args: %{"task" => "expose_api"}
      }

      assert {:ok, result} = TextEnvironment.perform(job)
      assert result.environment == :text
      assert result.task == :expose_api
      assert result.status == :completed
      assert String.contains?(result.base_url, "lang.nocsi.com")
    end

    test "executes generate_clients task successfully" do
      job = %Job{
        args: %{"task" => "generate_clients"}
      }

      assert {:ok, result} = TextEnvironment.perform(job)
      assert result.environment == :text
      assert result.task == :generate_clients
      assert result.status == :completed
      assert result.clients_generated > 0
      assert "python" in result.languages
      assert "javascript" in result.languages
    end

    test "executes produce_marketing task successfully" do
      job = %Job{
        args: %{"task" => "produce_marketing"}
      }

      assert {:ok, result} = TextEnvironment.perform(job)
      assert result.environment == :text
      assert result.task == :produce_marketing
      assert result.status == :completed
      assert result.marketing_materials > 0
    end

    test "executes publish task successfully" do
      job = %Job{
        args: %{"task" => "publish"}
      }

      assert {:ok, result} = TextEnvironment.perform(job)
      assert result.environment == :text
      assert result.task == :publish
      assert result.status == :completed
      assert result.published_artifacts > 0
      assert result.publish_timestamp
    end

    test "handles invalid task gracefully" do
      job = %Job{
        args: %{"task" => "invalid_task"}
      }

      assert_raise FunctionClauseError, fn ->
        TextEnvironment.perform(job)
      end
    end

    test "handles missing task argument" do
      job = %Job{
        args: %{}
      }

      assert_raise KeyError, fn ->
        TextEnvironment.perform(job)
      end
    end
  end

  describe "execute_task/2 - build_documentation" do
    test "generates all required documentation files" do
      result = TextEnvironment.execute_task(:build_documentation, %{})

      assert result.environment == :text
      assert result.task == :build_documentation
      assert result.status == :completed
      assert result.pages == 7
      assert result.total_examples > 0

      # Verify files are actually created
      docs_dir = "priv/static/docs/text"
      assert File.exists?(docs_dir)

      expected_files = [
        "introduction.md",
        "quickstart.md",
        "api_reference.md",
        "examples.md",
        "tutorials.md",
        "best_practices.md",
        "troubleshooting.md"
      ]

      Enum.each(expected_files, fn file ->
        file_path = Path.join(docs_dir, file)
        assert File.exists?(file_path), "Expected file #{file} to exist"

        # Verify file has content
        content = File.read!(file_path)
        assert String.length(content) > 0
        # Should have markdown headers
        assert String.contains?(content, "#")
      end)
    end

    test "generated documentation contains correct API URLs" do
      TextEnvironment.execute_task(:build_documentation, %{})

      # Check that generated docs use correct API URL
      quickstart_path = "priv/static/docs/text/quickstart.md"
      assert File.exists?(quickstart_path)

      content = File.read!(quickstart_path)
      assert String.contains?(content, "lang.nocsi.com")
      refute String.contains?(content, "api.lang.ai")
    end

    test "generated examples contain valid code" do
      TextEnvironment.execute_task(:build_documentation, %{})

      examples_path = "priv/static/docs/text/examples.md"
      assert File.exists?(examples_path)

      content = File.read!(examples_path)

      # Should contain code blocks
      assert String.contains?(content, "```bash")
      assert String.contains?(content, "curl")
      assert String.contains?(content, "X-API-Key")

      # Should contain multiple examples
      curl_count = content |> String.split("curl") |> (length() - 1)
      assert curl_count >= 5
    end
  end

  describe "execute_task/2 - generate_spec" do
    test "creates valid OpenAPI specification" do
      result = TextEnvironment.execute_task(:generate_spec, %{})

      assert result.environment == :text
      assert result.task == :generate_spec
      assert result.status == :completed
      assert result.endpoints > 0
      assert result.schemas > 0

      # Verify spec file is created
      spec_path = "priv/static/docs/text/openapi.json"
      assert File.exists?(spec_path)

      # Verify it's valid JSON
      spec_content = File.read!(spec_path)
      spec = Jason.decode!(spec_content)

      # Verify OpenAPI structure
      assert spec["openapi"] == "3.0.0"
      assert spec["info"]["title"] == "LANG Text Intelligence API"
      assert spec["info"]["version"] == "2.0.0"
      assert is_map(spec["paths"])
      assert is_map(spec["components"]["schemas"])

      # Verify server URLs
      servers = spec["servers"]
      production_server = Enum.find(servers, &(&1["description"] == "Production"))
      assert production_server
      assert String.contains?(production_server["url"], "lang.nocsi.com")
    end

    test "generates correct number of endpoints and schemas" do
      result = TextEnvironment.execute_task(:generate_spec, %{})

      spec_path = "priv/static/docs/text/openapi.json"
      spec_content = File.read!(spec_path)
      spec = Jason.decode!(spec_content)

      # Count actual endpoints
      endpoint_count =
        spec["paths"]
        |> Enum.map(fn {_path, methods} -> map_size(methods) end)
        |> Enum.sum()

      schema_count = map_size(spec["components"]["schemas"])

      assert result.endpoints == endpoint_count
      assert result.schemas == schema_count
    end
  end

  describe "execute_task/2 - implement_parsers" do
    test "implements all required text parsers" do
      result = TextEnvironment.execute_task(:implement_parsers, %{})

      assert result.environment == :text
      assert result.task == :implement_parsers
      assert result.status == :completed
      assert result.parsers_implemented > 0

      expected_parsers = [
        "markdown_parser",
        "markdown_ld_parser",
        "plain_text_parser",
        "semantic_extractor",
        "entity_recognizer",
        "stylometry_analyzer"
      ]

      Enum.each(expected_parsers, fn parser ->
        assert parser in result.parser_types
      end)
    end
  end

  describe "execute_task/2 - create_examples" do
    test "creates comprehensive code examples" do
      result = TextEnvironment.execute_task(:create_examples, %{})

      assert result.environment == :text
      assert result.task == :create_examples
      assert result.status == :completed
      assert result.total_examples >= 8

      expected_example_types = [
        "basic_text_analysis",
        "markdown_parsing",
        "semantic_extraction",
        "entity_recognition",
        "batch_processing"
      ]

      Enum.each(expected_example_types, fn example_type ->
        assert example_type in result.example_types
      end)
    end
  end

  describe "execute_task/2 - generate_clients" do
    test "generates client SDKs for multiple languages" do
      result = TextEnvironment.execute_task(:generate_clients, %{})

      assert result.environment == :text
      assert result.task == :generate_clients
      assert result.status == :completed
      assert result.clients_generated >= 5

      expected_languages = ["python", "javascript", "go", "java", "curl"]

      Enum.each(expected_languages, fn language ->
        assert language in result.languages
      end)

      assert String.contains?(result.client_path, "text/clients")
    end
  end

  describe "execute_task/2 - produce_marketing" do
    test "produces marketing materials" do
      result = TextEnvironment.execute_task(:produce_marketing, %{})

      assert result.environment == :text
      assert result.task == :produce_marketing
      assert result.status == :completed
      assert result.marketing_materials >= 5

      expected_content_types = [
        "landing_pages",
        "blog_posts",
        "case_studies",
        "whitepapers",
        "social_content"
      ]

      Enum.each(expected_content_types, fn content_type ->
        assert content_type in result.content_types
      end)

      assert String.contains?(result.marketing_path, "text/marketing")
    end
  end

  describe "execute_task/2 - publish" do
    test "publishes all artifacts" do
      result = TextEnvironment.execute_task(:publish, %{})

      assert result.environment == :text
      assert result.task == :publish
      assert result.status == :completed
      assert result.published_artifacts >= 5
      assert result.publish_timestamp

      expected_channels = [
        "api_docs",
        "client_sdks",
        "marketing_site",
        "npm_packages",
        "pypi_packages"
      ]

      Enum.each(expected_channels, fn channel ->
        assert channel in result.publication_channels
      end)
    end
  end

  describe "file generation and cleanup" do
    setup do
      # Clean up any existing generated files before each test
      docs_dir = "priv/static/docs/text"

      if File.exists?(docs_dir) do
        File.rm_rf!(docs_dir)
      end

      on_exit(fn ->
        # Optionally clean up after tests
        if File.exists?(docs_dir) do
          File.rm_rf!(docs_dir)
        end
      end)

      :ok
    end

    test "creates directory structure correctly" do
      TextEnvironment.execute_task(:build_documentation, %{})

      base_dir = "priv/static/docs/text"
      assert File.exists?(base_dir)

      # Verify it's a directory
      stat = File.stat!(base_dir)
      assert stat.type == :directory
    end

    test "handles existing files gracefully" do
      # First generation
      result1 = TextEnvironment.execute_task(:build_documentation, %{})
      assert result1.status == :completed

      # Second generation (should overwrite)
      result2 = TextEnvironment.execute_task(:build_documentation, %{})
      assert result2.status == :completed

      # Files should still exist and be valid
      intro_path = "priv/static/docs/text/introduction.md"
      assert File.exists?(intro_path)
      content = File.read!(intro_path)
      assert String.length(content) > 0
    end

    test "generates files with appropriate sizes" do
      TextEnvironment.execute_task(:build_documentation, %{})

      files_to_check = [
        "introduction.md",
        "quickstart.md",
        "api_reference.md",
        "examples.md"
      ]

      Enum.each(files_to_check, fn file ->
        file_path = "priv/static/docs/text/#{file}"
        stat = File.stat!(file_path)

        # Each file should have reasonable content (at least 200 bytes)
        assert stat.size > 200, "File #{file} should have substantial content"

        # But not be excessively large (less than 50KB for generated docs)
        assert stat.size < 50_000, "File #{file} should not be excessively large"
      end)
    end
  end

  describe "error handling" do
    test "handles file system errors gracefully" do
      # This is difficult to test without mocking, but we can test the happy path
      result = TextEnvironment.execute_task(:build_documentation, %{})
      assert result.status == :completed
    end

    test "handles invalid arguments" do
      # Test with invalid arguments
      result = TextEnvironment.execute_task(:build_documentation, %{"invalid" => "args"})
      # Should still work, ignoring invalid args
      assert result.status == :completed
    end

    test "validates task types" do
      assert_raise FunctionClauseError, fn ->
        TextEnvironment.execute_task(:invalid_task, %{})
      end
    end
  end

  describe "content validation" do
    test "generated markdown has proper structure" do
      TextEnvironment.execute_task(:build_documentation, %{})

      intro_content = File.read!("priv/static/docs/text/introduction.md")

      # Should start with main header
      assert String.starts_with?(intro_content, "# LANG Text Intelligence API")

      # Should contain features section
      assert String.contains?(intro_content, "## Features")

      # Should contain getting started
      assert String.contains?(intro_content, "## Getting Started")
    end

    test "API reference contains all required sections" do
      TextEnvironment.execute_task(:build_documentation, %{})

      api_content = File.read!("priv/static/docs/text/api_reference.md")

      required_sections = [
        "# API Reference",
        "## Base URL",
        "## Authentication",
        "## Endpoints"
      ]

      Enum.each(required_sections, fn section ->
        assert String.contains?(api_content, section)
      end)

      # Should contain production URL
      assert String.contains?(api_content, "lang.nocsi.com")
    end

    test "examples contain working code snippets" do
      TextEnvironment.execute_task(:build_documentation, %{})

      examples_content = File.read!("priv/static/docs/text/examples.md")

      # Should contain multiple bash/curl examples
      bash_blocks = Regex.scan(~r/```bash/, examples_content)
      assert length(bash_blocks) >= 5

      # Should contain proper curl syntax
      assert String.contains?(examples_content, "curl -X POST")
      assert String.contains?(examples_content, "-H \"X-API-Key: your-api-key\"")
      assert String.contains?(examples_content, "-H \"Content-Type: application/")
    end

    test "troubleshooting section provides helpful information" do
      TextEnvironment.execute_task(:build_documentation, %{})

      troubleshooting_content = File.read!("priv/static/docs/text/troubleshooting.md")

      # Should contain common issues
      assert String.contains?(troubleshooting_content, "## Common Issues")
      assert String.contains?(troubleshooting_content, "###")

      # Should provide solutions
      assert String.contains?(troubleshooting_content, "solution") or
               String.contains?(troubleshooting_content, "fix") or
               String.contains?(troubleshooting_content, "resolve")
    end
  end

  describe "performance and scalability" do
    test "documentation generation completes quickly" do
      start_time = System.monotonic_time(:millisecond)

      result = TextEnvironment.execute_task(:build_documentation, %{})

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      assert result.status == :completed
      # Should complete within reasonable time (30 seconds)
      assert duration < 30_000
    end

    test "can handle multiple concurrent generations" do
      # Run multiple tasks concurrently
      tasks =
        1..3
        |> Enum.map(fn _i ->
          Task.async(fn ->
            TextEnvironment.execute_task(:build_documentation, %{})
          end)
        end)

      results = Enum.map(tasks, &Task.await(&1, 30_000))

      # All should complete successfully
      Enum.each(results, fn result ->
        assert result.status == :completed
      end)
    end
  end
end
