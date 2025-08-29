defmodule Lang.Agent.Capabilities do
  @moduledoc """
  Utilities for querying agent, provider, and possible capabilities in the LANG system.
  """

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
end
