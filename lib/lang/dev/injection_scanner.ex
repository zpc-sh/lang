defmodule Lang.Dev.InjectionScanner do
  @moduledoc """
  Heuristic scanner for prompt/log injection patterns in Markdown.

  - Pure string/regex checks; no execution or HTML parsing.
  - Flags suspicious constructs so CI or dev UIs can surface them.
  - Non-blocking by default; separate lint task can fail builds.
  """

  @type finding :: %{
          type: atom(),
          severity: :low | :medium | :high,
          line: non_neg_integer(),
          snippet: String.t()
        }

  @doc """
  Scan a Markdown string and return a list of findings.
  """
  @spec scan_markdown(String.t()) :: [finding]
  def scan_markdown(text) when is_binary(text) do
    lines = String.split(text, "\n")
    Enum.with_index(lines, 1)
    |> Enum.flat_map(fn {line, idx} ->
      scan_line(line)
      |> Enum.map(fn {type, severity} -> %{type: type, severity: severity, line: idx, snippet: truncate(line)} end)
    end)
  end

  # Heuristic detectors per line
  defp scan_line(line) do
    Enum.flat_map([
      &detect_ignore_previous/1,
      &detect_role_headers/1,
      &detect_script_tags/1,
      &detect_event_handlers/1,
      &detect_js_uri/1,
      &detect_html_exec_lang/1
    ], fn f -> f.(line) end)
  end

  defp detect_ignore_previous(line) do
    if String.match?(line, ~r/(ignore|bypass)\s+(all|previous)\s+(instructions|safeguards)/i), do: [{:prompt_override, :medium}], else: []
  end

  defp detect_role_headers(line) do
    if String.match?(line, ~r/^(SYSTEM|DEVELOPER|USER|ASSISTANT)\s*:/i), do: [{:role_header, :low}], else: []
  end

  defp detect_script_tags(line) do
    if String.contains?(line, "<script") or String.contains?(line, "</script>") or String.contains?(line, "<iframe") do
      [{:html_script, :high}]
    else
      []
    end
  end

  defp detect_event_handlers(line) do
    if String.match?(line, ~r/ on[a-z]+\s*=\s*['"]/i), do: [{:html_event_handler, :medium}], else: []
  end

  defp detect_js_uri(line) do
    if String.match?(line, ~r/javascript:/i), do: [{:javascript_uri, :high}], else: []
  end

  defp detect_html_exec_lang(line) do
    if String.match?(line, ~r/^```(html|javascript|js|bash|sh)\b/i), do: [{:exec_lang_block, :low}], else: []
  end

  defp truncate(line) do
    line
    |> String.slice(0, 160)
    |> Lang.Dev.SafeText.sanitize()
  end
end

