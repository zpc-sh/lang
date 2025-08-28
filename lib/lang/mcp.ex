defmodule Lang.MCP do
  use Ash.Domain

  resources do
    resource(Lang.MCP.ServerConfig)
    resource(Lang.MCP.Connection)
    resource(Lang.MCP.Request)
  end
end
