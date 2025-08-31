defmodule Lang.Domains.Echo do
  @moduledoc """
  A simple example domain handler that echoes the input.
  Demonstrates the use of the `Lang.Router.DomainHandler` behaviour and macro.
  """

  # Use the macro to automatically implement the behaviour and register
  use Lang.Router.DomainHandler

  @impl true
  def can_handle?(input) when is_binary(input) do
    # Simple heuristic: if the input contains the word "echo", handle it.
    case String.contains?(String.downcase(input), "echo") do
      true -> {:score, 0.8} # High confidence if "echo" is present
      false -> {:score, 0.1} # Low confidence otherwise, acts as a fallback
    end
  end
  def can_handle?(_input), do: false # Don't handle non-binary inputs

  @impl true
  def prepare(input) when is_binary(input) do
    # For echo, preparation is just trimming whitespace
    String.trim(input)
  end

  @impl true
  def answer(prepared_input) when is_binary(prepared_input) do
    # The core logic: echo the prepared input
    case parse_echo_command(prepared_input) do
      {:ok, text_to_echo} ->
        # Simulate some work/delay
        # In a real domain, this could be a database call, file op, etc.
        Process.sleep(100)
        {:ok, %{type: :echo, content: "Echoing: #{text_to_echo}"}}
      :error ->
        # If we can't parse it as an echo command, we can't answer definitively
        {:continue, "Input recognized as echo-like but command format invalid."}
    end
  end

  # Parses the command. Expects "echo <text>"
  defp parse_echo_command("echo " <> rest), do: {:ok, rest}
  defp parse_echo_command(_other), do: :error

  @impl true
  def cost_class(), do: :low

  @impl true
  def max_ms(), do: 500

  @impl true
  def max_tokens(), do: 0 # Not an LLM domain

  # Optional callback
  @impl true
  def handoff_hints(_prepared_input), do: []
end