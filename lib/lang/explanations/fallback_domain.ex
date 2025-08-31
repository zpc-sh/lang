defmodule Lang.Domains.Fallback do
  @moduledoc """
  A fallback domain handler that catches inputs no other domain wanted.
  It has a very low score, so it only runs if all others pass.
  """

  use Lang.Router.DomainHandler

  @impl true
  def can_handle?(_input) do
    # Always available as a last resort, but with very low confidence.
    {:score, 0.01}
  end

  @impl true
  def prepare(input), do: input

  @impl true
  def answer(prepared_input) do
    # This domain provides a generic "I didn't understand" response.
    {:ok, %{type: :fallback, content: "I'm not sure how to handle that request: '#{prepared_input}'. Could you rephrase or provide more details?"}}
  end

  @impl true
  def cost_class(), do: :low

  @impl true
  def max_ms(), do: 100

  @impl true
  def max_tokens(), do: 0

  @impl true
  def handoff_hints(_prepared_input), do: []
end