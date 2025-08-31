defmodule Lang.Router.DomainHandler do
  @moduledoc """
  Defines the behaviour for all domain handlers registered with the Lang.Router.

  A domain handler is responsible for determining if it can process a query,
  preparing the input, and providing an answer.

  This behaviour ensures a consistent interface for the router to interact
  with a diverse set of domain-specific logic modules.

  Modules should `use Lang.Router.DomainHandler` to automatically register.
  """

  # -- Behaviour Definition (Unchanged) --
  @typedoc "The raw input query or command."
  @type input :: term()

  @typedoc "The input after being normalized/processed by `prepare/1`."
  @type prepared_input :: term()

  @typedoc "The result returned by the domain handler on success."
  @type result :: term()

  @typedoc "The reason for continuing or erroring."
  @type reason :: term()

  @typedoc """
  The response from the `answer/1` function.
  - `{:ok, result}`: The domain successfully produced a final answer.
  - `{:continue, reason}`: The domain cannot produce a final answer,
     routing should continue to the next layer.
  - `{:error, reason}`: An error occurred within the domain.
  """
  @type answer_response :: {:ok, result()} | {:continue, reason()} | {:error, reason()}

  @typedoc "The cost class for routing and budgeting."
  @type cost_class :: :low | :medium | :high

  @doc """
  Determines if the domain can handle the given input.

  This is the first check the router performs.

  Returns:
  - `true`: The domain is confident it can handle this.
  - `false`: The domain cannot handle this.
  - `{:score, float()}`: A probabilistic confidence score between 0.0 and 1.0.
  """
  @callback can_handle?(input()) :: true | false | {:score, float()}

  @doc """
  Prepares the input for processing by the `answer/1` function.

  This might involve parsing, normalization, enrichment, etc.
  It's run *after* `can_handle?/1` returns true or a positive score.
  """
  @callback prepare(input()) :: prepared_input()

  @doc """
  Executes the domain's core logic to produce an answer.

  This is where the domain does its work (e.g., database read, native computation).
  It should respect the `max_ms/0` and `max_tokens/0` limits.

  Returns `answer_response()`.
  """
  @callback answer(prepared_input()) :: answer_response()

  @doc """
  Indicates the computational cost/latency class of this domain.

  Used by the router for prioritization and budgeting.
  """
  @callback cost_class() :: cost_class()

  @doc """
  The maximum time (in milliseconds) this domain's `answer/1` is allowed to run.

  The router should enforce this limit.
  """
  @callback max_ms() :: integer()

  @doc """
  (For LLM-based domains) The maximum number of tokens this domain is allowed to consume.

  The router or the domain itself should enforce this limit.
  """
  @callback max_tokens() :: integer()

  @doc """
  (Optional) Provides hints for handoff to other domains.

  If a domain processes part of a query and knows another domain might be needed next,
  it can return a list of suggested domain names here.
  """
  @callback handoff_hints(prepared_input()) :: [domain_name :: atom()]
  # Make handoff_hints optional
  @optional_callbacks handoff_hints: 1

  # -- Macro Definition --
  @doc """
  A macro to be `use`d by modules implementing this behaviour.

  It automatically:
  1. Adds `@behaviour Lang.Router.DomainHandler`.
  2. Registers the module with `Lang.Router` at compile time.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Lang.Router.DomainHandler

      # Register the module with the router at compile time
      # The `after_compile` hook ensures the module is fully compiled before registration.
      @after_compile Lang.Router.DomainHandler
    end
  end

  # This callback is invoked after the module is compiled.
  def __after_compile__(%{module: module}, _binary) do
    # Register the compiled module with the router
    # We use `send/2` to avoid compile-time dependency issues.
    # The Router agent needs to be running.
    try do
      # Ensure the Router agent is started (idempotent if already started)
      # In a real app, this would be handled by the application supervisor.
      # For now, we attempt to start it.
      case Lang.Router.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, reason} -> raise "Failed to start Lang.Router agent: #{inspect(reason)}"
      end

      # Send a message to the Router agent to register the module
      Agent.cast(Lang.Router, fn registry ->
        # Check if not already registered (basic deduplication)
        if module not in registry do
          IO.puts("Registering domain handler: #{module}")
          [module | registry]
        else
          registry
        end
      end)
    rescue
      e ->
        IO.warn("Failed to register domain #{module} after compile: #{inspect(e)}")
    end
  end
end