defmodule Lang.LSP.Protocol.Types do
  @moduledoc false

  defmodule Request do
    @moduledoc false
    @enforce_keys [:id, :method]
    defstruct id: nil,
              method: nil,
              params: %{},
              client_id: nil

    @type t :: %__MODULE__{
            id: any(),
            method: String.t(),
            params: map() | any(),
            client_id: any()
          }
  end
end

