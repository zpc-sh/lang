defmodule Lang.MCP.ToolRegistry do
  @moduledoc """
  Registry of MCP tools exposed by LANG. Each tool maps to an LSP method and
  an optional argument mapping function.

  This is intentionally minimal; extend gradually as you harden routes.
  """

  @type tool_spec :: %{
          group: String.t(),
          lsp_method: String.t(),
          map_args: (map() -> map()) | nil,
          description: String.t()
        }

  @tools %{
    # Tokens
    "lang.tokens.estimate" => %{
      group: "tokens",
      lsp_method: "lang.tokens.estimate",
      map_args: nil,
      description: "Estimate token cost for an operation"
    },
    "lang.tokens.compress" => %{
      group: "tokens",
      lsp_method: "lang.tokens.compress",
      map_args: nil,
      description: "Compress context according to target ratio"
    },
    # Filesystem (NIF-backed)
    "lang.fs.preview" => %{
      group: "filesystem",
      lsp_method: "lang.fs.preview",
      map_args: nil,
      description: "Preview first N lines of a file"
    },
    # Analyze
    "lang.analyze.document" => %{
      group: "analysis",
      lsp_method: "lang.analyze.document",
      map_args: nil,
      description: "Analyze a single document"
    }
  }

  @spec list() :: [{String.t(), tool_spec()}]
  def list, do: Enum.to_list(@tools)

  @spec get(String.t()) :: {:ok, tool_spec()} | :error
  def get(name) when is_binary(name) do
    case Map.fetch(@tools, name) do
      {:ok, spec} -> {:ok, spec}
      :error -> :error
    end
  end

  @doc """
  Group tools for advertisement. Returns a list like:
    [%{group: "tokens", tools: [%{name: ..., description: ...}, ...]}, ...]
  """
  @spec grouped() :: list(map())
  def grouped do
    @tools
    |> Enum.group_by(fn {name, spec} -> spec.group || infer_group(name) end)
    |> Enum.map(fn {group, entries} ->
      %{
        group: group,
        tools:
          Enum.map(entries, fn {name, spec} ->
            %{name: name, description: spec.description}
          end)
      }
    end)
    |> Enum.sort_by(& &1.group)
  end

  defp infer_group(name) do
    name
    |> String.split(".")
    # drop "lang"
    |> Enum.drop(1)
    |> List.first()
    |> to_string()
  end
end
