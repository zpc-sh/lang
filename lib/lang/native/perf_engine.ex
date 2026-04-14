defmodule Lang.Native.PerfEngine do
  defmodule TripleResult do
    defstruct [:success, :error, :result]
  end
  def compare_triples(_a, _b, _o), do: {:error, :nif_not_loaded}
end
