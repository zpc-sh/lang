#!/usr/bin/env elixir

defmodule SimpleURLFix do
  @moduledoc """
  Simple and direct URL replacement script for LANG platform.
  Fixes critical URL issues without complex logic.
  """

  def run do
    IO.puts("🔧 Simple URL Fix Script")
    IO.puts("=" |> String.duplicate(40))

    # Define replacements
    replacements = [
      {"lang.nocsi.com", "lang.nocsi.com"},
      {"lang.nocsi.com", "lang.nocsi.com"},
      {"https://lang.nocsi.com", "https://lang.nocsi.com"},
      {"https://lang.nocsi.com", "https://lang.nocsi.com"},
      {"https://lang.nocsi.com", "https://lang.nocsi.com"},
      {"https://lang.nocsi.com", "https://lang.nocsi.com"}
    ]

    # Find all files to process (only our project files)
    files =
      [
        # Documentation files in our project
        Path.wildcard("*.md"),
        Path.wildcard("priv/docs/**/*.md"),
        Path.wildcard("priv/static/docs/**/*.md"),
        # Source files
        Path.wildcard("lib/lang/**/*.ex"),
        Path.wildcard("lib/lang_web/**/*.ex"),
        Path.wildcard("lib/lang_web/**/*.heex"),
        # Scripts
        Path.wildcard("scripts/**/*.exs")
      ]
      |> List.flatten()
      |> Enum.filter(&File.exists?/1)
      |> Enum.filter(fn file ->
        # Exclude dependency files
        !String.starts_with?(file, "deps/") and
          !String.starts_with?(file, "_build/") and
          !String.contains?(file, "node_modules")
      end)
      |> Enum.uniq()

    IO.puts("Processing #{length(files)} files...")

    {files_changed, replacements_made} =
      Enum.reduce(files, {0, 0}, fn file, {files_acc, replace_acc} ->
        original_content = File.read!(file)

        # Apply all replacements
        new_content =
          Enum.reduce(replacements, original_content, fn {old, new}, content ->
            String.replace(content, old, new)
          end)

        if new_content != original_content do
          File.write!(file, new_content)

          # Count how many replacements were made
          replacement_count =
            Enum.reduce(replacements, 0, fn {old, _new}, acc ->
              old_count = length(Regex.scan(~r/#{Regex.escape(old)}/, original_content))
              acc + old_count
            end)

          IO.puts("  ✅ Fixed #{file} (#{replacement_count} replacements)")
          {files_acc + 1, replace_acc + replacement_count}
        else
          {files_acc, replace_acc}
        end
      end)

    IO.puts("\n📊 Summary:")
    IO.puts("Files changed: #{files_changed}")
    IO.puts("Total replacements: #{replacements_made}")

    if files_changed > 0 do
      IO.puts("\n✅ URL fixes applied successfully!")
      IO.puts("Next: Test the application to ensure all URLs work correctly")
    else
      IO.puts("\n🎉 No URLs needed fixing - all correct!")
    end
  end
end

# Run the fix
SimpleURLFix.run()
