defmodule Lang.Agent do
  @moduledoc """
  Agent domain for LANG's cognitive operating system.

  This domain manages AI agents with their capabilities, security profiles,
  behavioral monitoring, and coordination mechanisms.
  """

  use Ash.Domain

  resources do
    resource(Lang.Agent.Agent)
    resource(Lang.Agent.BehavioralSample)
  end

  authorization do
    require_actor?(false)
    authorize(:by_default)
  end
end
