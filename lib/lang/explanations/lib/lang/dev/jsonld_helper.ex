defmodule Lang.Dev.JSONLDHelper do
  @moduledoc """
  Helpers for working with JSON‑LD models in dev.

  Provides hashing (sha256) and a minimal validation focused on required keys
  used by the DevKit. Intended for dev-only use.
  """

  @required_keys ["lds:action"]

  def parse(json) when is_binary(json) do
    try do
      {:ok, Jason.decode!(json)}
    rescue
      _ -> {:error, :invalid_json}
    end
  end

  # Backward-friendly raw hash (kept for reference); prefer canonical_hash/1.
  def hash(json) when is_binary(json) do
    :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)
  end

  @doc """
  Deterministic, canonical hash of a JSON‑LD structure.
  - Accepts a JSON string or a map.
  - Sorts map keys recursively and encodes without pretty printing.
  """
  def canonical_hash(json) when is_binary(json) do
    case parse(json) do
      {:ok, map} -> canonical_hash(map)
      _ -> hash(json)
    end
  end
  def canonical_hash(map) when is_map(map) do
    map
    |> canonicalize()
    |> Jason.encode!()
    |> hash()
  end

  @doc """
  Canonicalize a JSON‑LD map by recursively sorting keys and canonicalizing nested structures.
  """
  def canonicalize(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {k, canonicalize(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.into(%{})
  end
  def canonicalize(list) when is_list(list), do: Enum.map(list, &canonicalize/1)
  def canonicalize(other), do: other

  def validate(map) when is_map(map) do
    missing = Enum.filter(@required_keys, fn k -> Map.get(map, k) in [nil, ""] end)
    if missing != [], do: {:error, {:missing_keys, missing}}, else: validate_fields(map)
  end

  defp validate_fields(map) do
    case Map.get(map, "lds:action") do
      action when is_binary(action) ->
        if valid_action_id?(action), do: :ok, else: {:error, {:invalid_action_id, action}}
      _ -> {:error, {:invalid_action_id, nil}}
    end
  end

  # Conservative allowlist for action identifiers: namespaced/URI-like but safe.
  # Allows letters, digits, dot, colon, slash, dash, underscore, and hash.
  @action_re ~r/^[A-Za-z0-9._:\/\-#]{1,256}$/
  def valid_action_id?(action) when is_binary(action), do: Regex.match?(@action_re, action)

  def model_id(map, fallback \\ nil) do
    Map.get(map, "lds:action") || fallback
  end
end
