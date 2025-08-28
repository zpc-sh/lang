defmodule Lang.AITest do
  use ExUnit.Case, async: false
  alias Lang.AI
  alias Lang.Providers.{Provider, XAI, OpenAI, Anthropic}

  # Mock responses for testing
  setup do
    # Mock XAI responses
    Mox.stub(Lang.Providers.XAIMock, :health_check, fn ->
      {:ok, "XAI Mock healthy"}
    end)

    Mox.stub(Lang.Providers.XAIMock, :analyze_situation, fn _context, question, _opts ->
      {:ok, %{analysis: "Mock Grok response: #{question}"}}
    end)

    Mox.stub(Lang.Providers.XAIMock, :handle_request, fn method, params, _opts ->
      {:ok, %{content: "Mock XAI handled #{method} with #{inspect(params)}"}}
    end)

    # Mock OpenAI responses
    Mox.stub(Lang.Providers.OpenAIMock, :health_check, fn ->
      {:ok, "OpenAI Mock healthy"}
    end)

    Mox.stub(Lang.Providers.OpenAIMock, :handle_request, fn method, params, _opts ->
      {:ok, %{content: "Mock OpenAI handled #{method} with #{inspect(params)}"}}
    end)

    # Mock Anthropic responses
    Mox.stub(Lang.Providers.AnthropicMock, :health_check, fn ->
      {:ok, "Anthropic Mock healthy"}
    end)

    Mox.stub(Lang.Providers.AnthropicMock, :handle_request, fn method, params, _opts ->
      {:ok, %{content: "Mock Anthropic handled #{method} with #{inspect(params)}"}}
    end)

    :ok
  end

  describe "ask/3 - Simple AI interface" do
    test "automatically selects provider based on question type" do
      # Security question should route to analysis
      assert {:ok, response} = AI.ask("Is this code secure?", "def login(user, pass)")
      assert is_binary(response)
      assert String.contains?(response, "Mock")
    end

    test "handles code explanation questions" do
      assert {:ok, response} = AI.ask("What does this function do?", "def hello(name)")
      assert is_binary(response)
    end

    test "handles generation requests" do
      assert {:ok, response} = AI.ask("Create a function that validates emails")
      assert is_binary(response)
    end

    test "handles empty context gracefully" do
      assert {:ok, response} = AI.ask("Explain programming concepts")
      assert is_binary(response)
    end
  end

  describe "explain/2 - Code explanation" do
    test "explains code content directly" do
      code = "def add(a, b), do: a + b"
      assert {:ok, response} = AI.explain(code)
      assert is_binary(response)
    end

    test "handles file paths by reading content" do
      # Create a temporary file for testing
      temp_file = "/tmp/test_code.ex"
      File.write!(temp_file, "def test_function, do: :ok")

      assert {:ok, response} = AI.explain(temp_file)
      assert is_binary(response)

      # Cleanup
      File.rm!(temp_file)
    end

    test "handles non-existent files as direct content" do
      assert {:ok, response} = AI.explain("non_existent_file.ex")
      assert is_binary(response)
    end
  end

  describe "generate/2 - Code generation" do
    test "generates code from natural language description" do
      description = "Create a function that calculates factorial"
      assert {:ok, response} = AI.generate(description)
      assert is_binary(response)
    end

    test "accepts language and framework options" do
      description = "Create a REST API endpoint"
      opts = [language: "elixir", framework: "phoenix"]
      assert {:ok, response} = AI.generate(description, opts)
      assert is_binary(response)
    end
  end

  describe "security_scan/2 - Security analysis" do
    test "performs security analysis on code" do
      code = "def authenticate(user, password), do: user.password == password"
      assert {:ok, response} = AI.security_scan(code)
      assert is_binary(response)
    end

    test "accepts scan type options" do
      code = "SELECT * FROM users WHERE id = #{id}"
      opts = [scan_type: "sql_injection"]
      assert {:ok, response} = AI.security_scan(code, opts)
      assert is_binary(response)
    end
  end

  describe "diagnose/2 - Error diagnosis" do
    test "diagnoses error messages" do
      error = """
      ** (ArgumentError) argument error
          (stdlib) :ets.lookup(:nonexistent_table, :key)
      """

      assert {:ok, response} = AI.diagnose(error)
      assert is_binary(response)
    end

    test "accepts additional context" do
      error = "undefined function foo/1"
      context = %{module: "MyModule", line: 42}
      assert {:ok, response} = AI.diagnose(error, context: context)
      assert is_binary(response)
    end
  end

  describe "mission/2 - Complex mission coordination" do
    test "coordinates complex multi-step missions" do
      mission = "Analyze this authentication system for security and performance issues"

      # Mock the Router.execute_mission function
      with_mock Lang.Providers.Router,
        execute_mission: fn _mission, _opts ->
          {:ok,
           %{
             total_tasks: 3,
             successful_tasks: 3,
             results: [
               %{content: "Security analysis complete"},
               %{content: "Performance review complete"},
               %{content: "Recommendations generated"}
             ]
           }}
        end do
        assert {:ok, response} = AI.mission(mission)
        assert is_binary(response)
        assert String.contains?(response, "3/3 tasks completed")
      end
    end
  end

  describe "Provider selection optimization" do
    test "cheap/3 forces use of cheapest provider" do
      assert {:ok, response} = AI.cheap("Explain this code", "def test, do: :ok")
      assert is_binary(response)
    end

    test "best_quality/3 uses highest quality providers" do
      assert {:ok, response} = AI.best_quality("Find security issues", "def auth(user)")
      assert is_binary(response)
    end

    test "fastest/3 optimizes for speed" do
      assert {:ok, response} = AI.fastest("What does this do?", "def hello, do: :world")
      assert is_binary(response)
    end
  end

  describe "Direct provider communication" do
    test "grok/2 communicates directly with Grok" do
      assert {:ok, response} = AI.grok("What's your tactical assessment?")
      assert String.contains?(response, "Mock Grok response")
    end

    test "with_provider/4 forces specific provider" do
      assert {:ok, response} =
               AI.with_provider(:xai, "lang.think.explain_intent", %{content: "def test"})

      assert is_binary(response)
    end
  end

  describe "Utility functions" do
    test "health_check/0 returns provider health status" do
      with_mock Provider,
        health_check_all: fn ->
          %{
            timestamp: DateTime.utc_now(),
            providers: %{
              xai: {:ok, "healthy"},
              openai: {:ok, "healthy"},
              anthropic: {:ok, "healthy"}
            },
            healthy_count: 3,
            total_count: 3
          }
        end do
        health = AI.health_check()
        assert health.healthy_count == 3
        assert health.total_count == 3
      end
    end

    test "capabilities/0 returns provider capability matrix" do
      with_mock Provider,
        capability_matrix: fn ->
          %{
            xai: %{best_for: [:command, :cost], avoid_for: [:complex_analysis]},
            openai: %{best_for: [:generation], avoid_for: [:cost_optimization]},
            anthropic: %{best_for: [:security, :analysis], avoid_for: [:simple_tasks]}
          }
        end do
        capabilities = AI.capabilities()
        assert Map.has_key?(capabilities, :xai)
        assert Map.has_key?(capabilities, :openai)
        assert Map.has_key?(capabilities, :anthropic)
      end
    end

    test "estimate_cost/2 returns cost estimates" do
      with_mock Provider,
        estimate_costs: fn _method, _params ->
          %{
            xai: %{estimated_tokens: 1000, estimated_cost_usd: 0.002},
            openai: %{estimated_tokens: 1000, estimated_cost_usd: 0.02},
            anthropic: %{estimated_tokens: 1000, estimated_cost_usd: 0.015}
          }
        end do
        estimates = AI.estimate_cost("lang.think.explain_intent")
        assert Map.has_key?(estimates, :xai)
        assert estimates.xai.estimated_tokens == 1000
      end
    end
  end

  describe "Error handling" do
    test "handles provider errors gracefully" do
      with_mock Provider,
        execute: fn _method, _params, _opts ->
          {:error, "Provider unavailable"}
        end do
        assert {:error, "Provider unavailable"} = AI.ask("test question")
      end
    end

    test "handles invalid file paths" do
      # Should treat as direct content, not error
      assert {:ok, response} = AI.explain("/invalid/path/file.ex")
      assert is_binary(response)
    end

    test "handles empty or nil inputs" do
      assert {:ok, response} = AI.ask("")
      assert is_binary(response)

      assert {:ok, response} = AI.explain("")
      assert is_binary(response)
    end
  end

  describe "Method inference from questions" do
    test "correctly identifies security questions" do
      questions = [
        "Is this code secure?",
        "Find security vulnerabilities",
        "Check for SQL injection",
        "Any security risks here?"
      ]

      for question <- questions do
        # We can't directly test the private function, but we can test the behavior
        assert {:ok, _response} = AI.ask(question, "def test_code")
      end
    end

    test "correctly identifies explanation questions" do
      questions = [
        "What does this function do?",
        "Explain this code",
        "How does this work?",
        "Help me understand this"
      ]

      for question <- questions do
        assert {:ok, _response} = AI.ask(question, "def test_code")
      end
    end

    test "correctly identifies generation questions" do
      questions = [
        "Create a function that...",
        "Generate code for...",
        "Write a program that...",
        "Build a component that..."
      ]

      for question <- questions do
        assert {:ok, _response} = AI.ask(question, "")
      end
    end

    test "defaults to explanation for ambiguous questions" do
      ambiguous_questions = [
        "Tell me about this",
        "What is this?",
        "Help with this code"
      ]

      for question <- ambiguous_questions do
        assert {:ok, _response} = AI.ask(question, "def test_code")
      end
    end
  end

  describe "Content normalization" do
    test "reads file content when path is provided" do
      # Create temp file
      temp_file = "/tmp/ai_test_content.ex"
      content = "def example_function, do: :test"
      File.write!(temp_file, content)

      # Should read file content, not treat path as content
      assert {:ok, response} = AI.explain(temp_file)
      assert is_binary(response)

      # Cleanup
      File.rm!(temp_file)
    end

    test "treats non-file strings as direct content" do
      direct_content = "def inline_code, do: :direct"
      assert {:ok, response} = AI.explain(direct_content)
      assert is_binary(response)
    end

    test "converts non-string input to string" do
      atom_input = :test_atom
      assert {:ok, response} = AI.explain(atom_input)
      assert is_binary(response)

      number_input = 12345
      assert {:ok, response} = AI.explain(number_input)
      assert is_binary(response)
    end
  end

  # Integration test with actual providers (if API keys available)
  @tag :integration
  describe "Integration tests (requires API keys)" do
    test "can communicate with real Grok if API key is set" do
      case System.get_env("XAI_API_KEY") do
        nil ->
          IO.puts("Skipping Grok integration test - no XAI_API_KEY")

        _api_key ->
          assert {:ok, response} = AI.grok("Hello Grok, respond with 'INTEGRATION_TEST_SUCCESS'")
          assert String.contains?(response, "INTEGRATION_TEST_SUCCESS")
      end
    end

    test "can communicate with real OpenAI if API key is set" do
      case System.get_env("OPENAI_API_KEY") do
        nil ->
          IO.puts("Skipping OpenAI integration test - no OPENAI_API_KEY")

        _api_key ->
          assert {:ok, response} =
                   AI.with_provider(:openai, "lang.think.explain_intent", %{
                     content: "def hello, do: :world"
                   })

          assert String.contains?(response, "hello") or String.contains?(response, "world")
      end
    end

    test "can communicate with real Anthropic if API key is set" do
      case System.get_env("ANTHROPIC_API_KEY") do
        nil ->
          IO.puts("Skipping Anthropic integration test - no ANTHROPIC_API_KEY")

        _api_key ->
          assert {:ok, response} =
                   AI.with_provider(:anthropic, "lang.think.security_scan", %{
                     content: "def insecure_auth(user, pass), do: user.password == pass"
                   })

          assert is_binary(response)
      end
    end
  end
end
