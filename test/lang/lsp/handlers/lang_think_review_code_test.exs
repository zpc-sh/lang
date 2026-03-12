defmodule Lang.LSP.Handlers.LangThinkReviewCodeTest do
  use ExUnit.Case

  alias Lang.LSP.Handlers.LangThinkReviewCode

  describe "perform_code_review/1" do
    test "returns success message for valid Elixir module" do
      code = """
      defmodule ValidModule do
        def hello do
          IO.puts("Hello, world!")
        end
      end
      """

      assert LangThinkReviewCode.perform_code_review(code) ==
               "Code compiled successfully. No obvious issues found during basic static analysis."
    end

    test "returns compilation error for module with syntax error" do
      code = """
      defmodule InvalidModule do
        def hello do
          IO.puts("Hello, world!"  # Missing closing parenthesis
        end
      end
      """

      assert String.contains?(LangThinkReviewCode.perform_code_review(code), "Compilation error")
    end

    test "returns warning for module using IO.inspect" do
      code = """
      defmodule DebugModule do
        def debug do
          IO.inspect("Debugging...")
        end
      end
      """

      assert String.contains?(
               LangThinkReviewCode.perform_code_review(code),
               "Warning: Found `IO.inspect` call"
             )
    end

    test "returns 'No code provided' message for empty string" do
      assert LangThinkReviewCode.perform_code_review("") == "No code provided for review."
    end

    test "returns 'No code provided' message for nil" do
      assert LangThinkReviewCode.perform_code_review(nil) == "No code provided for review."
    end
  end
end