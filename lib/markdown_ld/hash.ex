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
    json = encode_stable(term)
    hash = :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)
    {:ok, %{algorithm: "sha256", form: "stable-json", hash: hash, quad_count: 0}}
  end

  defp encode_stable(term) when is_map(term) do
    term
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.into(%{}, fn {k, v} -> {k, encode_stable(v)} end)
    |> Jason.encode_to_iodata!()
  end

  defp encode_stable(list) when is_list(list),
    do: Jason.encode_to_iodata!(Enum.map(list, &encode_stable/1))

  defp encode_stable(other), do: Jason.encode_to_iodata!(other)
end
