# defmodule Lang.Polyglot.Concealment do
#   @moduledoc """
#   Methods for concealing data in markdown using its permissive grammar.

#   Since markdown ::= .*, we can hide data anywhere without breaking rendering.
#   """

#   @zero_width_chars %{
#     # Zero-width space
#     "0" => "\u200B",
#     # Zero-width non-joiner
#     "1" => "\u200C",
#     # Zero-width joiner
#     "2" => "\u200D",
#     # Word joiner
#     "3" => "\u2060",
#     # Zero-width no-break space
#     "4" => "\uFEFF",
#     # Mongolian vowel separator
#     "5" => "\u180E",
#     # Function application
#     "6" => "\u2061",
#     # Invisible times
#     "7" => "\u2062",
#     # Invisible separator
#     "8" => "\u2063",
#     # Invisible plus
#     "9" => "\u2064"
#   }

#   @doc """
#   Hide data using zero-width Unicode characters.
#   (Internal) The data should be metadata only, not credentials.
#   """
#   def hide_zero_width(text, data) do
#     encoded =
#       data
#       |> :erlang.term_to_binary()
#       |> Base.encode64()
#       |> String.graphemes()
#       |> Enum.map(&encode_char/1)
#       |> Enum.join()

#     text <> encoded
#   end

#   @doc """
#   Extract data from zero-width characters.
#   """
#   def extract_zero_width(text) do
#     text
#     |> String.graphemes()
#     |> Enum.filter(&zero_width?/1)
#     |> Enum.map(&decode_char/1)
#     |> Enum.join()
#     |> Base.decode64!()
#     |> :erlang.binary_to_term()
#   rescue
#     _ -> nil
#   end

#   @doc """
#   Hide data in content-addressed links.

#   ## Example

#       iex> Concealment.hide_in_link("deployment guide", "docker build -t app .")
#       "[deployment guide](e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855)"
#   """
#   def hide_in_link(text, content) do
#     hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
#     "[#{text}](#{hash})"
#   end

#   @doc """
#   Hide data in whitespace patterns.

#   Uses newline counts to encode binary data.
#   """
#   def hide_in_whitespace(text, data) do
#     encoded =
#       data
#       |> :erlang.term_to_binary()
#       |> :binary.bin_to_list()
#       |> Enum.map(fn byte ->
#         # Each byte becomes newlines (max 5 to avoid suspicion)
#         String.duplicate("\n", rem(byte, 5) + 1)
#       end)
#       # Separate with CR
#       |> Enum.join("\r")

#     text <> "\n\n" <> encoded
#   end

#   @doc """
#   Hide data in HTML comments with various encodings.
#   """
#   def hide_in_comment(data, encoding \\ :base64) do
#     encoded = encode_data(data, encoding)
#     "<!-- polyglot:#{encoding}:#{encoded} -->"
#   end

#   @doc """
#   Hide metadata in code fence attributes (internal use).
#   """
#   def hide_in_fence_attributes(lang, code, metadata) do
#     attrs = metadata_to_attributes(metadata)
#     "```#{lang} #{attrs}\n#{code}\n```"
#   end

#   @doc """
#   Hide data in Pandoc-style divs.
#   """
#   def hide_in_div(content, metadata) do
#     """
#     ::: {.polyglot #{metadata_to_attributes(metadata)}}
#     #{content}
#     :::
#     """
#   end

#   @doc """
#   Extract all concealed data from markdown.
#   """
#   def extract_all(markdown) do
#     %{
#       zero_width: extract_zero_width(markdown),
#       comments: extract_from_comments(markdown),
#       links: extract_from_links(markdown),
#       whitespace: extract_from_whitespace(markdown),
#       attributes: extract_from_attributes(markdown)
#     }
#     |> Enum.reject(fn {_, v} -> is_nil(v) or v == [] end)
#     |> Map.new()
#   end

#   # Private functions

#   defp encode_char(char) do
#     Map.get(@zero_width_chars, char, "\u200B")
#   end

#   defp decode_char(char) do
#     @zero_width_chars
#     |> Enum.find(fn {_, v} -> v == char end)
#     |> case do
#       {k, _} -> k
#       nil -> ""
#     end
#   end

#   defp zero_width?(char) do
#     char in Map.values(@zero_width_chars)
#   end

#   defp encode_data(data, :base64) do
#     data |> :erlang.term_to_binary() |> Base.encode64()
#   end

#   defp encode_data(data, :hex) do
#     data |> :erlang.term_to_binary() |> Base.encode16(case: :lower)
#   end

#   defp encode_data(data, :json) do
#     Jason.encode!(data)
#   end

#   defp metadata_to_attributes(metadata) do
#     metadata
#     |> Enum.map(fn
#       {k, true} -> ".#{k}"
#       {k, false} -> nil
#       {k, v} when is_binary(v) -> ~s(#{k}="#{v}")
#       {k, v} -> ~s(#{k}=#{inspect(v)})
#     end)
#     |> Enum.reject(&is_nil/1)
#     |> Enum.join(" ")
#   end

#   defp extract_from_comments(markdown) do
#     ~r/<!-- polyglot:(\w+):(.*?) -->/
#     |> Regex.scan(markdown)
#     |> Enum.map(fn [_, encoding, data] ->
#       decode_data(data, String.to_atom(encoding))
#     end)
#     |> Enum.reject(&is_nil/1)
#   end

#   defp extract_from_links(markdown) do
#     ~r/\[[^\]]+\]\(([a-f0-9]{64})\)/
#     |> Regex.scan(markdown)
#     |> Enum.map(fn [_, hash] -> %{type: :content_link, hash: hash} end)
#   end

#   defp extract_from_whitespace(markdown) do
#     # This is complex - simplified for now
#     nil
#   end

#   defp extract_from_attributes(markdown) do
#     ~r/```\w+\s+\{([^}]+)\}/
#     |> Regex.scan(markdown)
#     |> Enum.map(fn [_, attrs] -> parse_attributes(attrs) end)
#   end

#   defp decode_data(data, :base64) do
#     case Base.decode64(data) do
#       {:ok, binary} -> :erlang.binary_to_term(binary)
#       _ -> nil
#     end
#   rescue
#     _ -> nil
#   end

#   defp decode_data(data, :hex) do
#     case Base.decode16(data, case: :lower) do
#       {:ok, binary} -> :erlang.binary_to_term(binary)
#       _ -> nil
#     end
#   rescue
#     _ -> nil
#   end

#   defp decode_data(data, :json) do
#     Jason.decode(data)
#   rescue
#     _ -> nil
#   end

#   defp parse_attributes(attrs_string) do
#     # Simplified attribute parsing
#     %{attributes: attrs_string}
#   end
# end
