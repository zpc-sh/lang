defmodule Lang.Native.FSWatcher do
  def watch(_p), do: {:error, :nif_not_loaded}
end
