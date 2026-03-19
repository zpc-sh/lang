defmodule Lang.LSP.Protocol.Response do
  @moduledoc false

  defstruct id: nil,
            result: nil,
            error: nil

  @type t :: %__MODULE__{
          id: any(),
          result: any() | nil,
          error: any() | nil
        }
end

