defmodule Lang.Dev.Drift do
  @moduledoc """
  Drift detection between the dev ModelRegistry (ETS) and rendered docs.

  Compares the registry's canonical hash for each model against the hash
  embedded in the generated Markdown frontmatter.
  """

  import Ash.Query
  alias Lang.Dev.ModelRegistry
  alias Lang.Dev.DocRenderer

  @type drift_item :: %{id: String.t(), registry_hash: String.t(), doc_hash: String.t() | nil}

  @doc """
  Returns a list of drift items with mismatched or missing doc hashes.
  """
  @spec report() :: [drift_item]
  def report do
    case ModelRegistry |> Ash.read() do
      {:ok, models} ->
        models
        |> Enum.map(&compare_doc/1)
        |> Enum.filter(& &1)
      _ -> []
    end
  end

  defp compare_doc(%{model_id: id, hash: reg_hash}) do
    doc_path = Path.join(DocRenderer.output_dir(), id <> ".md")
    case File.read(doc_path) do
      {:ok, content} ->
        case DocRenderer.parse_frontmatter(content) do
          {:ok, fm, _body} ->
            case Map.get(fm, "hash") do
              ^reg_hash -> nil
              other -> %{id: id, registry_hash: reg_hash, doc_hash: other}
            end
          {:error, _} -> %{id: id, registry_hash: reg_hash, doc_hash: nil}
        end
      {:error, _} -> %{id: id, registry_hash: reg_hash, doc_hash: nil}
    end
  end
end

