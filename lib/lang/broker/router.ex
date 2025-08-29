defmodule Lang.Broker.Router do
  @moduledoc """
  Registry for protocol implementations by service name and a small helper
  to resolve a protocol module for a new session.
  """

  @type service :: atom()

  @protocols %{
    mcp: Lang.MCP.Protocol,
    dap: nil
  }

  @spec resolve(service()) :: {:ok, module()} | :error
  def resolve(svc) do
    case Map.fetch(@protocols, svc) do
      {:ok, mod} when is_atom(mod) and not is_nil(mod) -> {:ok, mod}
      _ -> :error
    end
  end
end
