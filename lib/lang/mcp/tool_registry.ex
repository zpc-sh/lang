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

  defp spec_tools do
    %{
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
    },
    # ML Operations
    "lang.ml.anomaly.stats" => %{
      group: "ml",
      lsp_method: "lang.ml.anomaly.stats",
      map_args: nil,
      description: "Get ML anomaly detection statistics"
    },
    "lang.ml.usage.predict" => %{
      group: "ml",
      lsp_method: "lang.ml.usage.predict",
      map_args: fn args -> %{"user_id" => args["user_id"], "time_window" => args["time_window"] || "hour"} end,
      description: "Predict MCP usage for a user"
    },
    "lang.ml.anomaly.train" => %{
      group: "ml",
      lsp_method: "lang.ml.anomaly.train",
      map_args: nil,
      description: "Trigger ML model training for anomaly detection"
    }
    }
  end

  @spec list() :: [{String.t(), tool_spec()}]
  def list do
    Map.to_list(tools())
  end

  defp tools, do: spec_tools()

  defp runtime_tools do
    %{
      "filesystem" => %{
        "scan" => %{
          "description" => "Scan a directory",
          "function" => &Lang.Native.FSScanner.scan/2,
          "schema" => %{
            "type" => "object",
            "properties" => %{
              "path" => %{"type" => "string"},
              "max_depth" => %{"type" => "integer"}
            },
            "required" => ["path"]
          }
        },
        "read" => %{
          "description" => "Read a file",
          "function" => fn path -> File.read(path) end,
          "schema" => %{
            "type" => "object",
            "properties" => %{"path" => %{"type" => "string"}},
            "required" => ["path"]
          }
        }
      },
      "shell" => %{
        "execute" => %{
          "description" => "Execute a shell command",
          "function" => fn cmd -> System.cmd(cmd, []) end,
          "schema" => %{
            "type" => "object",
            "properties" => %{"command" => %{"type" => "string"}},
            "required" => ["command"]
          }
        }
      }
    }
  end

  @spec get(String.t()) :: {:ok, tool_spec()} | :error
  def get(name) when is_binary(name) do
    case Map.fetch(tools(), name) do
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
    tools()
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
