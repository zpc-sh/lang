defmodule Lang.MCP.Domain do
  use Ash.Domain

  resources do
    resource Lang.MCP.Resources.ServerConfig
    resource Lang.MCP.Resources.Connection
    # Placeholder resources to satisfy relationships; expand as needed
    resource Lang.MCP.Resources.Session
    resource Lang.MCP.Resources.Request
  end
end
