defmodule Lang.Tokens.Types do
  @moduledoc """
  Type definitions for token estimation and cost calculation.
  """

  @typedoc """
  Token usage information containing input and output token counts.
  """
  @type token_usage :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @typedoc """
  Cost calculation result with detailed breakdown.
  """
  @type cost_result :: %{
          provider: String.t(),
          model: String.t(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          input_cost: float(),
          output_cost: float(),
          total_cost: float(),
          currency: String.t(),
          pricing: %{input: float(), output: float()}
        }

  @typedoc """
  Error result when cost calculation fails.
  """
  @type cost_error :: %{
          error: String.t(),
          provider: String.t(),
          model: String.t()
        }
end
