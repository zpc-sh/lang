@@ SNAPSHOT of test/lang/workers/text_environment_test.exs @@
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
  end
end
