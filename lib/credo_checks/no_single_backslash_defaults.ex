defmodule CredoChecks.NoSingleBackslashDefaults do
  @moduledoc """
  Flags accidental single backslashes in default arguments, e.g.:

      def foo(opts \ []), do: :ok    # valid
      def foo(opts \ []), do: :ok    # valid
      def foo(opts \ []), do: :ok    # valid

  But this is invalid and will not compile:

      def foo(opts \ []), do: :ok    # invalid (single backslash)

  This check catches patterns like "\\ []", "\\ nil", "\\ %{}", "\\ {}", "\\ ()".
  """

  use Credo.Check, category: :readability, base_priority: :high

  @patterns ["\\ []", "\\ nil", "\\ %", "\\ {}", "\\ ()"]

  @impl true
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.SourceFile.lines_with_endings()
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {line, ln}, acc ->
      if contains_bad_default?(line) do
        [issue_for(issue_meta, ln, String.trim(line)) | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp contains_bad_default?(line) when is_binary(line) do
    Enum.any?(@patterns, &String.contains?(line, &1))
  end

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message: "Invalid single backslash in default arg. Use \\\\ or multiple heads.",
      trigger: trigger,
      line_no: line_no
    )
  end
end

