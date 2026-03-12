defmodule MarkdownLd.Diff.Format do
  @moduledoc """
  Conflict formatter for UI and logs.

  Provides text and map renderers for `MarkdownLd.Diff.Conflict` values, with
  useful context such as path and before/after snippets when available.
  """

  alias MarkdownLd.Diff

  @doc """
  Format conflicts as a list of strings.
  """
  @spec to_text([Diff.Conflict.t()]) :: [String.t()]
  def to_text(conflicts) do
    Enum.map(conflicts, &format_conflict_text/1)
  end

  @doc """
  Format conflicts as maps for structured consumption by UIs.
  """
  @spec to_maps([Diff.Conflict.t()]) :: [map()]
  def to_maps(conflicts) do
    Enum.map(conflicts, &format_conflict_map/1)
  end

  defp format_conflict_text(%Diff.Conflict{reason: reason, path: path, ours: o, theirs: t}) do
    opath = path_to_string(path)
    {ob, oa} = extract_before_after(o)
    {tb, ta} = extract_before_after(t)
    "conflict #{reason} at #{opath}\n  ours: #{truncate(oa || inspect(o))}\n  theirs: #{truncate(ta || inspect(t))}"
  end

  defp format_conflict_map(%Diff.Conflict{reason: reason, path: path, ours: o, theirs: t}) do
    {ob, oa} = extract_before_after(o)
    {tb, ta} = extract_before_after(t)
    %{
      reason: reason,
      path: path,
      ours: %{kind: o && o.kind, before: ob, after: oa},
      theirs: %{kind: t && t.kind, before: tb, after: ta}
    }
  end

  defp path_to_string(nil), do: "/"
  defp path_to_string(list) when is_list(list), do: "/" <> Enum.map_join(list, "/", &to_string/1)
  defp path_to_string(_), do: "/"

  defp extract_before_after(%Diff.Change{payload: p}) when is_map(p) do
    {p[:before], p[:after]}
  end
  defp extract_before_after(_), do: {nil, nil}

  defp truncate(nil), do: nil
  defp truncate(str) when is_binary(str) do
    if String.length(str) > 200, do: String.slice(str, 0, 200) <> "…", else: str
  end
end

