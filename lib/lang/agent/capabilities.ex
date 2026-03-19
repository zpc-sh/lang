defmodule Lang.Agent.Capabilities do
  @moduledoc """
  Utilities for querying agent, provider, and possible capabilities in the LANG system.
  """
  alias Lang.Redis

  alias Lang.Agent.Agent

  @doc """
  Returns a map of agent IDs to their capabilities.
  """
  def all_agent_capabilities do
    case Agent.read_all() do
      {:ok, agents} ->
        Enum.map(agents, &{&1.id, &1.capabilities})
        |> Enum.into(%{})

      {:error, _} ->
        %{}
    end
  end

  @doc """
  Returns all possible capabilities in the system.
  """
  def all_possible_capabilities do
    Lang.Providers.Capabilities.list_capabilities()
  end

  @doc """
  Returns a summary of all providers and their capabilities.
  """
  def all_provider_capabilities do
    Lang.Providers.Capabilities.get_all_capabilities()
  end

  @doc """
  Registers an agent with detailed capabilities schema and stores ephemerally in Redis.
  Capabilities should be a list of maps with domain, skills, proficiency.
  """
  def register_agent(agent_id, capabilities) when is_list(capabilities) do
    # Validate schema
    if Enum.all?(capabilities, &valid_capability?/1) do
      # Store in Redis as JSON with 1-hour TTL
      json = Jason.encode!(capabilities)
      Redis.set("agent:registry:#{agent_id}", json, ex: 3600)

      # Optionally sync to Ash for persistence
      case Agent.read_by_id(agent_id) do
        {:ok, agent} ->
          # Map detailed to flat atoms if needed, but for now just update metadata
          Agent.update(agent, %{metadata: %{detailed_capabilities: capabilities}})

        _ ->
          # If no Ash agent, just use Redis
          :ok
      end

      {:ok, agent_id}
    else
      {:error, :invalid_capabilities_schema}
    end
  end

  @doc """
  Gets detailed capabilities for an agent, checking Redis first, then Ash fallback.
  """
  def get_detailed_capabilities(agent_id) do
    case Redis.get("agent:registry:#{agent_id}") do
      nil ->
        # Fallback to Ash
        case Agent.read_by_id(agent_id) do
          {:ok, agent} ->
            Map.get(agent.metadata, :detailed_capabilities, [])

          _ ->
            []
        end

      json ->
        Jason.decode!(json)
    end
  end

  defp valid_capability?(%{domain: d, skills: s, proficiency: p})
       when is_binary(d) and is_list(s) and is_number(p) and p >= 0.0 and p <= 1.0 do
    true
  end

  defp valid_capability?(_), do: false
end
