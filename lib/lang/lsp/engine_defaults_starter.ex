defmodule Lang.LSP.EngineDefaultsStarter do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    # Defer registration until the LSP Engine is up
    Process.send_after(self(), :register, 0)
    {:ok, %{attempts: 0}}
  end

  @impl true
  def handle_info(:register, %{attempts: attempts} = state) do
    case wait_for_engine(100, 30) do
      :ok ->
        safe_register()
        {:noreply, state}

      :timeout ->
        # Give up quietly in case LSP is disabled at runtime
        {:noreply, state}

      :retry ->
        Process.send_after(self(), :register, 100)
        {:noreply, %{state | attempts: attempts + 1}}
    end
  end

  defp wait_for_engine(_interval_ms, 0), do: :timeout
  defp wait_for_engine(interval_ms, retries) do
    if Process.whereis(Lang.LSP.Engine) do
      :ok
    else
      if retries > 0, do: :retry, else: :timeout
    end
  end

  defp safe_register do
    try do
      if Code.ensure_loaded?(Lang.LSP.EngineDefaults) do
        Lang.LSP.EngineDefaults.register_defaults()
      end
    rescue
      _ -> :ok
    end
  end
end

