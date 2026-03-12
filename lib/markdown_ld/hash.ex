defmodule MarkdownLD.Hash do
  @moduledoc """
  Lightweight integrity helpers for JSON-LD/Markdown-LD.

  Preferred approach is URDNA2015 → canonical N-Quads → SHA-256.
  As a pragmatic fallback (no remote contexts, no canonicalizer), we provide
  a deterministic JSON hashing by sorting keys recursively before encoding.
  """

  @type integrity :: %{
          algorithm: String.t(),
          form: String.t(),
          hash: String.t(),
          quad_count: non_neg_integer()
        }

  @doc """
  Compute a deterministic hash for a JSON/JSON-LD term.

  If a canonicalizer is available, prefer URDNA2015; otherwise, fallback
  to stable JSON (sorted keys).
  """
  def dataset_hash(term) do
    # TODO: try canonical N-Quads when a URDNA2015 canonicalizer is wired
    normalized = normalize(term)
    json = Jason.encode_to_iodata!(normalized)
    hash = :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)
    {:ok, %{algorithm: "sha256", form: "stable-json", hash: hash, quad_count: 0}}
  end

  # Normalize into a JSON-encodable structure with stable key ordering.
  # Do NOT pre-encode substructures; only encode once at the top.
  defp normalize(term) when is_map(term) do
    term
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.into(%{}, fn {k, v} -> {k, normalize(v)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)

  defp normalize(other) do
    case other do
      a when is_atom(a) and a not in [true, false, nil] -> to_string(a)
      %DateTime{} = dt -> DateTime.to_iso8601(dt)
      %NaiveDateTime{} = ndt -> NaiveDateTime.to_iso8601(ndt)
      %Date{} = d -> Date.to_iso8601(d)
      %Time{} = t -> Time.to_iso8601(t)
      _ -> other
    end
  end
end
