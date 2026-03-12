defmodule Lang.LSP.Engine do
  @moduledoc """
  Brokering engine for language-aware request routing.

  Goals:
  - Centralize knowledge of the LSP spec via Lang.LSP.Spec (positions/ranges)
  - Broker requests to language-specific handlers or external backends
  - Provide a pluggable registry (language -> backend handler)

  Backends can be:
  - A local module implementing `handle(method, params, ctx)`
  - An MFA `{mod, fun, extra}`
  - An anonymous function `(method, params, ctx) -> result`
  """

  use GenServer

  @type language :: String.t() | atom()
  @type handler :: module() | {module(), atom(), any()} | (binary(), map(), map() -> any())

  # Public API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.merge([name: __MODULE__], opts))
  end

  @doc """
  Register a backend for a given language.
  """
  @spec register(language(), handler()) :: :ok
  def register(lang, handler) do
    GenServer.call(__MODULE__, {:register, normalize_lang(lang), handler})
  end

  @doc """
  Unregister backend for language.
  """
  def unregister(lang), do: GenServer.call(__MODULE__, {:unregister, normalize_lang(lang)})

  @doc """
  Route an LSP-esque request to the registered backend.
  Returns `{:ok, result}` | `{:error, reason}`.
  """
  @spec route(language(), binary(), map(), map()) :: {:ok, any()} | {:error, any()}
  def route(lang, method, params, ctx \\ %{}) do
    case GenServer.call(__MODULE__, {:get, normalize_lang(lang)}) do
      {:ok, handler} ->
        safe_invoke(handler, method, params, ctx)
      :not_found ->
        {:error, {:no_backend, lang}}
    end
  end

  # GenServer callbacks
  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:register, lang, handler}, _from, state) do
    {:reply, :ok, Map.put(state, lang, handler)}
  end

  @impl true
  def handle_call({:unregister, lang}, _from, state) do
    {:reply, :ok, Map.delete(state, lang)}
  end

  @impl true
  def handle_call({:get, lang}, _from, state) do
    case Map.fetch(state, lang) do
      {:ok, handler} -> {:reply, {:ok, handler}, state}
      :error -> {:reply, :not_found, state}
    end
  end

  # Helpers
  defp normalize_lang(lang) when is_atom(lang), do: Atom.to_string(lang)
  defp normalize_lang(lang) when is_binary(lang), do: String.downcase(lang)

  defp safe_invoke(fun, method, params, ctx) when is_function(fun, 3) do
    try do
      {:ok, fun.(method, params, ctx)}
    rescue
      e -> {:error, {:backend_error, e}}
    end
  end

  defp safe_invoke({m, f, extra}, method, params, ctx) do
    try do
      {:ok, apply(m, f, [method, params, ctx, extra])}
    rescue
      e -> {:error, {:backend_error, e}}
    end
  end

  defp safe_invoke(mod, method, params, ctx) when is_atom(mod) do
    try do
      if function_exported?(mod, :handle, 2), do: {:ok, apply(mod, :handle, [params, ctx])},
        else: invoke_by_method(mod, method, params, ctx)
    rescue
      e -> {:error, {:backend_error, e}}
    end
  end

  defp invoke_by_method(mod, method, params, ctx) do
    fun = method_to_fun(method)
    if function_exported?(mod, fun, 2), do: {:ok, apply(mod, fun, [params, ctx])}, else: {:error, :no_handler}
  end

  defp method_to_fun(meth) when is_binary(meth) do
    meth
    |> String.replace([".", "/"], "_")
    |> String.to_atom()
  end
end

