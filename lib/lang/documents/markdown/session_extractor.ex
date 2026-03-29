defmodule Lang.Documents.Markdown.SessionExtractor do
  @moduledoc """
  Pulls executable JSON blocks out of Markdown: Sessions, ConnectionProfiles, and Intents.

  This does not parse prose. It scans fenced code blocks (```json / ```jsonld)
  and Polyglot concealment channels (comments) for JSON maps.
  """

  alias Lang.Polyglot.Concealment

  @type extracted :: %{sessions: [map()], profiles: [map()], intents: [map()], other: [map()]}

  @spec extract(String.t()) :: extracted()
  def extract(markdown) when is_binary(markdown) do
    blocks =
      extract_fenced_json(markdown) ++
        extract_concealed_json(markdown)

    Enum.reduce(blocks, %{sessions: [], profiles: [], intents: [], other: []}, fn m, acc ->
      case classify(m) do
        :session -> update_in(acc[:sessions], &[m | &1])
        :profile -> update_in(acc[:profiles], &[m | &1])
        :intent -> update_in(acc[:intents], &[m | &1])
        :other -> update_in(acc[:other], &[m | &1])
      end
    end)
    |> Enum.into(%{}, fn {k, v} -> {k, Enum.reverse(v)} end)
  end

  defp extract_fenced_json(markdown) do
    # ```json ... ``` or ```jsonld ... ```
    regex = ~r/```(json|jsonld)\s+([\s\S]*?)```/m
    for [_, _lang, body] <- Regex.scan(regex, markdown),
        {:ok, map} <- [safe_decode(body)],
        is_map(map), do: map
  end

  defp extract_concealed_json(markdown) do
    case Concealment.extract_all(markdown) do
      %{} = concealed ->
        concealed
        |> Map.values()
        |> List.wrap()
        |> List.flatten()
        |> Enum.filter(&is_map/1)

      _ -> []
    end
  end

  defp classify(%{"@type" => t} = _m) when is_binary(t) do
    case String.downcase(t) do
      "session" -> :session
      "connectionprofile" -> :profile
      "intent" -> :intent
      _ -> :other
    end
  end
  defp classify(_), do: :other

  defp safe_decode(str) do
    str = String.trim(str)
    try do
      Jason.decode(str)
    rescue
      _ -> {:error, :invalid_json}
    end
  end
end

