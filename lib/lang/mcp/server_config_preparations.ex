defmodule Lang.MCP.ServerConfig.Preparations do
  @moduledoc false

  # Preparation should return a query as-is for now
  def add_json_ld_context(query), do: query
  def add_json_ld_context(query, _opts), do: query
  def add_json_ld_context(query, _opts, _ctx), do: query
end
