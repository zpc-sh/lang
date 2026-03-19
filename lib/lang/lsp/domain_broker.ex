defmodule Lang.LSP.DomainBroker do
  @moduledoc """
  Behaviour for LSP domain brokers.

  A broker isolates a domain's heavy logic (potentially in a separate VM), exposing
  a uniform `handle/2` API that accepts a JSON-RPC request map and a
  `Lang.LSP.Configuration`.
  """

  alias Lang.LSP.Configuration

  @type jsonrpc_request :: map()
  @type result :: {:ok, any()} | {:error, integer(), String.t()} | {:error, integer(), String.t(), map()}

  @callback init(Configuration.t()) :: {:ok, any()} | {:error, any()}
  @callback handle(jsonrpc_request, Configuration.t()) :: result
  @callback terminate(any()) :: :ok

  @optional_callbacks init: 1, terminate: 1
end

