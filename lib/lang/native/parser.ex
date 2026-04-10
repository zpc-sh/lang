defmodule Lang.Native.Parser do
  defmodule ParseResult do
    defstruct [:success, :error, :ast, :format, :tokens, :errors, :processing_time_us, :functions, :classes]
  end
  def parse(_c), do: {:error, :nif_not_loaded}
end
