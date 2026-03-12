defmodule Lang.Codegen.Naming do
  @moduledoc """
  Helpers for building stable module and method names from loosely
  structured inputs (Markdown/JSON-LD derived), preventing double
  prefixes like "Elixir.Lang.LSP.Lang.Lang..." and method keys like
  "lang.lang.tokens.compress".

  Usage examples:

      # Module names
      Lang.Codegen.Naming.module_name(["LSP", "Handlers", "Tokens", "Compress"])
      # => "Lang.LSP.Handlers.Tokens.Compress"

      Lang.Codegen.Naming.module_name(["Lang", "LSP", "Lang", "Tokens", "Estimate"]) 
      # => "Lang.LSP.Tokens.Estimate"

      # Method keys
      Lang.Codegen.Naming.method_name(["lang", "tokens", "compress"]) 
      # => "lang.tokens.compress"

      Lang.Codegen.Naming.method_name(["lang", "lang", "tokens", "compress"]) 
      # => "lang.tokens.compress"
  """

  @doc """
  Build a module name string from segments, ensuring exactly one root (default "Lang"),
  stripping any accidental "Elixir." prefixes, camelizing segments, and case-insensitive
  de-duplication of adjacent segments.
  """
  @spec module_name([term()], keyword()) :: String.t()
  def module_name(raw_segments, opts \\ []) when is_list(raw_segments) do
    root = opts[:root] || "Lang"

    [root | raw_segments]
    |> Enum.flat_map(&split_and_clean/1)
    |> Enum.map(&Macro.camelize/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> dedupe_adjacent_ci()
    |> Enum.join(".")
  end

  @doc """
  Build a method name like "lang.tokens.compress" from parts. Lowercases segments,
  de-dupes a double "lang" head (e.g., ["lang","lang",...]).
  """
  @spec method_name([term()]) :: String.t()
  def method_name(parts) when is_list(parts) do
    parts
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.downcase/1)
    |> drop_double_lang_head()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(".")
  end

  # --- helpers ---

  defp split_and_clean(seg) when is_atom(seg), do: split_and_clean(Atom.to_string(seg))

  defp split_and_clean(seg) when is_binary(seg) do
    seg
    |> String.trim()
    |> String.replace_leading("Elixir.", "")
    |> String.split([".", "/"], trim: true)
  end

  defp split_and_clean(_), do: []

  defp dedupe_adjacent_ci([]), do: []
  defp dedupe_adjacent_ci([h | t]), do: do_dedupe_adjacent_ci([h], t)

  defp do_dedupe_adjacent_ci(acc, []), do: acc

  defp do_dedupe_adjacent_ci(acc, [h | t]) do
    last = List.last(acc)

    if String.downcase(h) == String.downcase(last) do
      do_dedupe_adjacent_ci(acc, t)
    else
      do_dedupe_adjacent_ci(acc ++ [h], t)
    end
  end

  defp drop_double_lang_head(["lang", "lang" | rest]), do: ["lang" | rest]
  defp drop_double_lang_head(list), do: list
end
