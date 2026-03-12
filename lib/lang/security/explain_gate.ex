defmodule Lang.Security.ExplainGate do
  @moduledoc """
  Core Explanation Gate interface.

  Seam to an external Explanation Engine to evaluate high-risk operations
  (e.g., session connects). Returns a verdict with a confidence score.

  Default implementation is permissive; replace with a real integration.
  """

  @type attrs :: map()
  @type verdict :: :allow | :deny | :revise
  @type result :: {:ok, %{verdict: verdict, score: float(), rationale: String.t()}} | {:error, term()}

  @spec evaluate_connect(any(), any(), attrs()) :: result()
  def evaluate_connect(_user, _org, attrs) when is_map(attrs) do
    {:ok, %{verdict: :allow, score: 0.95, rationale: "default-allow (stub)"}}
  end
end

