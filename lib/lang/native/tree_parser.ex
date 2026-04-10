defmodule Lang.Native.TreeParser do
  def parse(_c), do: {:error, :nif_not_loaded}
end
