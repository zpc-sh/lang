defmodule Lang.LSP.EngineAdapter do
  @moduledoc """
  Adapter for the Engine Elixir LSP that injects into a VM.

  This module is intentionally defensive: it checks for the configured Engine
  module and functions at runtime and degrades gracefully if unavailable.

  Configure with `config :lang, :lsp_engine_module, YourEngineModule`.
  Defaults to `Engine` (top-level) if present.
  """

  @type pos :: %{line: non_neg_integer(), character: non_neg_integer()}
  @type range :: %{start: pos(), end: pos()}

  @callback symbols(map()) :: {:ok, [map()]} | {:error, term()}
  @callback references(map()) :: {:ok, [map()]} | {:error, term()}
  @callback definitions(map()) :: {:ok, [map()]} | {:error, term()}
  @callback hover(map()) :: {:ok, map()} | {:error, term()}
  @callback semantic_tokens(map()) :: {:ok, map()} | {:error, term()}
  # Optional streaming callbacks (provider may implement)
  @callback symbols_stream(map(), (map() -> any())) :: :ok | {:error, term()}
  @callback references_stream(map(), (map() -> any())) :: :ok | {:error, term()}
  @callback definitions_stream(map(), (map() -> any())) :: :ok | {:error, term()}
  @callback hover_stream(map(), (map() -> any())) :: :ok | {:error, term()}
  @callback semantic_tokens_stream(map(), (map() -> any())) :: :ok | {:error, term()}

  @doc """
  Resolve the configured Engine module.
  """
  @spec engine_mod() :: module() | nil
  def engine_mod do
    mod = Application.get_env(:lang, :lsp_engine_module, Engine)
    if is_atom(mod) and Code.ensure_loaded?(mod), do: mod, else: nil
  end

  @spec symbols(map()) :: {:ok, [map()]} | {:error, term()}
  def symbols(params) do
    with mod when is_atom(mod) <- engine_mod(),
         true <- function_exported?(mod, :symbols, 1) do
      safe_call(fn -> mod.symbols(params) end)
    else
      _ -> {:error, :engine_unavailable}
    end
  end

  @doc """
  Stream partial symbol updates if the engine exposes a streaming function.
  The callback will be invoked with provider-specific partial payload maps.
  """
  @spec symbols_stream(map(), (map() -> any())) :: :ok | {:error, term()}
  def symbols_stream(params, cb) when is_function(cb, 1) do
    with mod when is_atom(mod) <- engine_mod(),
         true <- function_exported?(mod, :symbols_stream, 2) do
      safe_call_stream(fn -> mod.symbols_stream(params, cb) end)
    else
      _ -> {:error, :engine_unavailable}
    end
  end

  @spec references_stream(map(), (map() -> any())) :: :ok | {:error, term()}
  def references_stream(params, cb) when is_function(cb, 1) do
    with mod when is_atom(mod) <- engine_mod(),
         true <- function_exported?(mod, :references_stream, 2) do
      safe_call_stream(fn -> mod.references_stream(params, cb) end)
    else
      _ -> {:error, :engine_unavailable}
    end
  end

  @spec definitions_stream(map(), (map() -> any())) :: :ok | {:error, term()}
  def definitions_stream(params, cb) when is_function(cb, 1) do
    with mod when is_atom(mod) <- engine_mod(),
         true <- function_exported?(mod, :definitions_stream, 2) do
      safe_call_stream(fn -> mod.definitions_stream(params, cb) end)
    else
      _ -> {:error, :engine_unavailable}
    end
  end

  @spec hover_stream(map(), (map() -> any())) :: :ok | {:error, term()}
  def hover_stream(params, cb) when is_function(cb, 1) do
    with mod when is_atom(mod) <- engine_mod(),
         true <- function_exported?(mod, :hover_stream, 2) do
      safe_call_stream(fn -> mod.hover_stream(params, cb) end)
    else
      _ -> {:error, :engine_unavailable}
    end
  end

  @spec semantic_tokens_stream(map(), (map() -> any())) :: :ok | {:error, term()}
  def semantic_tokens_stream(params, cb) when is_function(cb, 1) do
    with mod when is_atom(mod) <- engine_mod(),
         true <- function_exported?(mod, :semantic_tokens_stream, 2) do
      safe_call_stream(fn -> mod.semantic_tokens_stream(params, cb) end)
    else
      _ -> {:error, :engine_unavailable}
    end
  end

  @spec references(map()) :: {:ok, [map()]} | {:error, term()}
  def references(params) do
    with mod when is_atom(mod) <- engine_mod(),
         true <- function_exported?(mod, :references, 1) do
      safe_call(fn -> mod.references(params) end)
    else
      _ -> {:error, :engine_unavailable}
    end
  end

  @spec definitions(map()) :: {:ok, [map()]} | {:error, term()}
  def definitions(params) do
    with mod when is_atom(mod) <- engine_mod(),
         true <- function_exported?(mod, :definitions, 1) do
      safe_call(fn -> mod.definitions(params) end)
    else
      _ -> {:error, :engine_unavailable}
    end
  end

  @spec hover(map()) :: {:ok, map()} | {:error, term()}
  def hover(params) do
    with mod when is_atom(mod) <- engine_mod(),
         true <- function_exported?(mod, :hover, 1) do
      safe_call(fn -> mod.hover(params) end)
    else
      _ -> {:error, :engine_unavailable}
    end
  end

  @spec semantic_tokens(map()) :: {:ok, map()} | {:error, term()}
  def semantic_tokens(params) do
    with mod when is_atom(mod) <- engine_mod(),
         true <- function_exported?(mod, :semantic_tokens, 1) do
      safe_call(fn -> mod.semantic_tokens(params) end)
    else
      _ -> {:error, :engine_unavailable}
    end
  end

  defp safe_call(fun) do
    try do
      case fun.() do
        {:ok, _} = ok -> ok
        {:error, _} = err -> err
        other -> {:error, {:invalid_engine_response, other}}
      end
    rescue
      e -> {:error, {:engine_exception, e}}
    catch
      :exit, reason -> {:error, {:engine_exit, reason}}
    end
  end

  defp safe_call_stream(fun) do
    try do
      case fun.() do
        :ok -> :ok
        {:error, _} = err -> err
        other -> {:error, {:invalid_engine_stream_response, other}}
      end
    rescue
      e -> {:error, {:engine_exception, e}}
    catch
      :exit, reason -> {:error, {:engine_exit, reason}}
    end
  end
end
