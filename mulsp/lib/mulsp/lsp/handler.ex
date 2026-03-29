defmodule Mulsp.LSP.Handler do
  @moduledoc """
  Behaviour for LSP method handlers.
  Each handler module implements handle/1 and returns {:ok, result} or {:error, code, message}.
  """

  @callback handle(request :: map()) :: {:ok, term()} | {:error, atom(), String.t()}
end
