defmodule Lang.LSP.BrokerRuntime do
  @moduledoc """
  Broker runtime orchestration (skeleton).

  Provides an abstraction to run domain brokers in-process or in external VMs,
  controlled by `Application.get_env(:lang, :lsp_brokers, [])[:mode]` which may be
  `:inproc` (default) or `:external`.

  External mode (expert-style) outline:
  - compile(domain, project_env) -> {:ok, artifact_paths}
  - start(domain, artifact_paths, opts) -> {:ok, pid_or_ref}
  - call(ref, request, config) -> {:ok, result} | {:error, code, message, data}
  - stop(ref) -> :ok
  """

  @type domain :: atom()
  @type artifact_paths :: [String.t()]
  @type ref :: term()

  @doc """
  Compile a domain for a given project environment. External mode only (skeleton).
  """
  @spec compile(domain, map()) :: {:ok, artifact_paths} | {:error, term()}
  def compile(_domain, _project_env) do
    case mode() do
      :external -> {:error, :not_implemented}
      _ -> {:ok, []}
    end
  end

  @doc """
  Start a domain runtime instance. External mode only (skeleton).
  """
  @spec start(domain, artifact_paths, keyword()) :: {:ok, ref} | {:error, term()}
  def start(_domain, _artifacts, _opts \\ []) do
    case mode() do
      :external -> {:error, :not_implemented}
      _ -> {:ok, self()}
    end
  end

  @doc """
  Call into a domain runtime instance. External mode only (skeleton).
  """
  @spec call(ref, map(), map()) :: {:ok, any()} | {:error, integer(), String.t(), map()}
  def call(_ref, _request, _config) do
    case mode() do
      :external -> {:error, -32050, "external_runtime_not_implemented", %{} }
      _ -> {:error, -32601, "inproc_only", %{}}
    end
  end

  @doc """
  Stop a domain runtime instance. External mode only (skeleton).
  """
  @spec stop(ref) :: :ok
  def stop(_ref), do: :ok

  defp mode do
    case Application.get_env(:lang, :lsp_brokers) do
      m when is_list(m) -> Keyword.get(m, :mode, :inproc)
      m when is_map(m) -> Map.get(m, :mode, :inproc)
      _ -> :inproc
    end
  end
end

