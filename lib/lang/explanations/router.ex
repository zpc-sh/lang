defmodule Lang.Router do
  @moduledoc """
  The deterministic router for the Lang system.

  Orchestrates the single-pass, forward-only routing pipeline:
  L0 (Auth handled upstream) ->
  L1 (Caches) ->
  L2 (Deterministic Domains) ->
  L3 (Small Model Triage) ->
  L4 (LLM Basecase).

  It uses a registry of domain handlers that implement the `Lang.Router.DomainHandler` behaviour.
  Domain handlers are registered explicitly.
  """

  alias Lang.Explanations.Core, as: ExplanationEngine

  # --- Registry Management (Compile-Time via Agent) ---
  use Agent

  @doc """
  Starts the Router agent which holds the registry of domain handlers.
  """
  def start_link(_opts) do
    # Initialize the registry as an empty list
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @doc """
  Explicitly registers a list of known domain handler modules with the router.
  This should be called during application startup.
  """
  def register_domains() do
    # List of domain modules to register
    domain_modules = [
      Lang.Domains.Echo,
      Lang.Domains.Fallback
      # Add more domain modules here as they are created
    ]

    Enum.each(domain_modules, fn module ->
      # Ensure the module is compiled and loaded
      case Code.ensure_compiled(module) do
        {:module, _} ->
          # Validate behaviour (basic check)
          if function_exported?(module, :can_handle?, 1) do
            # Add to registry if not already present
            current_registry = Agent.get(__MODULE__, & &1)
            if module not in current_registry do
              Agent.cast(__MODULE__, fn registry -> [module | registry] end)
              IO.puts("Registered domain handler: #{module}")
            else
              IO.puts("Domain handler #{module} already registered.")
            end
          else
             IO.warn("Module #{module} does not implement required DomainHandler functions. Skipping registration.")
          end
        {:error, reason} ->
          IO.warn("Failed to compile/load module #{module}: #{reason}. Skipping registration.")
      end
    end)
    :ok
  end

  @doc """
  Retrieves the list of currently registered domain handler modules.
  """
  def list_domains() do
    Agent.get(__MODULE__, & &1)
  end

  # --- Core Routing Pipeline ---
  @default_opts [
    allow_escalation: true,
    # Add other default options like cache timeouts, etc.
  ]

  @doc """
  Routes an input query through the L0-L4 pipeline.

  ## Options
   - `:allow_escalation` (boolean) - If false, prevents escalation to L3/L4.
      Defaults to `true`.
   - Other options for caches, timeouts, etc., can be added.

  ## Returns
   - `{:ok, result}` - A final answer was determined.
   - `{:continue, reason}` - No domain could answer, and escalation was disallowed or not possible.
   - `{:error, reason}` - An error occurred during routing or domain execution.
  """
  def route(input, context \\ %{}, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    # L0: Auth/Idempotency is assumed handled upstream before calling `route/3`.

    # --- L1: Cache Layer ---
    # Placeholder for cache logic
    # case check_caches(input, context) do
    #   {:hit, cached_result} -> {:ok, cached_result}
    #   :miss -> proceed_to_l2(input, context, opts)
    # end
    # For now, skip cache and go directly to L2
    proceed_to_l2(input, context, opts)
  end

  # Internal function for L2 logic
  defp proceed_to_l2(input, context, opts) do
     # --- L2: Deterministic Domains ---
    domains = list_domains()

    # Simple scoring for now (can be optimized)
    scored_domains =
      Enum.reduce(domains, [], fn domain_module, acc ->
         case domain_module.can_handle?(input) do
           true -> [{1.0, domain_module} | acc] # Treat true as max score
           false -> acc
           {:score, score} when is_number(score) and score > 0.0 -> [{score, domain_module} | acc]
           _ -> acc
         end
      end)
      |> Enum.sort_by(&elem(&1, 0), :desc) # Sort by score descending

    # Iterate through sorted domains
    # A more advanced version might batch or parallelize calls within budget constraints.
    attempt_domains(scored_domains, input, context, opts)
  end

  defp attempt_domains([], input, context, opts) do
    # No domains could handle it.
    # --- L3: Small Model Triage (Placeholder) ---
    if Keyword.get(opts, :allow_escalation, true) do
      # Placeholder for L3 call
      IO.puts("L2 domains exhausted, escalating to L3 (Small Model Triage - Placeholder)")
      # call_small_model_triage(input, context, opts)
      # For now, just go to L4
      proceed_to_l4(input, context, opts)
    else
      {:continue, "No deterministic domain could handle the input and escalation is disabled."}
    end
  end

  defp attempt_domains([{_score, domain_module} | rest], input, context, opts) do
    IO.puts("Trying domain: #{domain_module}")
    # Prepare input
    prepared_input = domain_module.prepare(input)

    # Execute with potential timeout/budget enforcement (simplified)
    # A real implementation would use Task.async with timeout or a custom executor
    try do
       # This is a simplified call. Real execution might need supervision/budgeting.
       case domain_module.answer(prepared_input) do
         {:ok, result} ->
           {:ok, result}
         {:continue, reason} ->
           # Log reason? Or pass it up?
           IO.puts("Domain #{domain_module} continued: #{reason}")
           # Try next domain
           attempt_domains(rest, input, context, opts)
         {:error, reason} ->
           # Log error? Decide whether to stop or continue?
           # For now, stop on error from a domain.
           IO.puts("Domain #{domain_module} errored: #{reason}")
           {:error, reason}
       end
    rescue
        e ->
          # Handle timeouts or other execution errors
          IO.warn("Domain #{domain_module} failed with exception: #{inspect(e)}")
          # Continue to next domain
          attempt_domains(rest, input, context, opts)
    end
  end

  # --- L3: Small Model Triage (Placeholder) ---
  # defp call_small_model_triage(input, context, opts) do
  #   # L3 Logic would go here
  #   # For now, proceed to L4
  #   proceed_to_l4(input, context, opts)
  # end

  # --- L4: LLM Basecase ---
  defp proceed_to_l4(input, context, opts) do
    IO.puts("Escalating to L4 (LLM Basecase)")

    # Check billing before calling expensive LLM
    # This is a simplification; real check might be more integrated
    # if not Keyword.get(opts, :billing_check_passed, true) do
    #   billing_service = Application.get_env(:lang, :billing_service, [])
    #   if billing_service[:module] && billing_service[:can_make_request?] do
    #     unless billing_service[:can_make_request?].(context) do
    #        IO.puts(\"Billing check failed for LLM escalation.\")
    #        # Should this be an error or continue?
    #        return {:error, \"Billing limit exceeded for LLM request\"}
    #     end
    #   end
    # end

    # Call the external Explanation Engine as the LLM basecase
    # This is a simplification; a real L4 might be a committee of LLMs
    user_id = Map.get(context, :user_id, "unknown_user")
    org_id = Map.get(context, :org_id, "unknown_org")

    # The attrs for the explanation engine are the input itself in this simplified view
    # A real system might need to transform the input or context
    attrs = %{query: input, context: context}

    case ExplanationEngine.evaluate_connect(user_id, org_id, attrs) do
      {:ok, %{verdict: :allow, score: score, rationale: rationale}} ->
        # If the explanation engine 'allows' it, we treat its rationale as the answer.
        # This is a simplification; a real L4 LLM would generate a direct response to the user's query.
        IO.puts("L4 LLM Basecase allowed with score #{score}: #{rationale}")
        {:ok, %{type: :llm_response, content: rationale, score: score}}
      {:ok, %{verdict: verdict, score: score, rationale: rationale}} when verdict in [:deny, :uncertain] ->
        IO.puts("L4 LLM Basecase returned verdict #{verdict} (score: #{score}): #{rationale}")
        # Deny or uncertain from the LLM basecase is a failure to route.
        {:error, "L4 LLM Basecase could not provide a definitive answer: #{verdict} - #{rationale}"}
      {:error, reason} ->
        IO.puts("L4 LLM Basecase call failed: #{reason}")
        {:error, "L4 LLM Basecase unavailable: #{reason}"}
    end
  end

  # Placeholder functions for other layers
  # defp check_caches(_input, _context) do
  #   # Implement cache check logic
  #   :miss
  # end

end
