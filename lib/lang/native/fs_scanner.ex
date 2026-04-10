defmodule Lang.Native.FSScanner do
  def scan(_p), do: {:error, :nif_not_loaded}
end
