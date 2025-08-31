defmodule Lang.Explanations.Core do
  @moduledoc """
  Core Explanation Engine interface (stub).

  This module is a seam to the Core Explanation Engine (e.g., Claude's service).
  It evaluates high-risk operations (like session connects) and returns a
  verdict with a confidence score and rationale. Replace this stub with the
  real engine integration when available.
  """

  @type attrs :: map()
  @type verdict :: :allow | :deny | :revise
  @type result :: {:ok, %{verdict: verdict, score: float(), rationale: String.t()}} | {:error, term()}

  @doc """
  Evaluate a prospective session connect request.
  Expects user/org context and the connect attrs (proto, host/path/url, caps, etc.).
  Returns a verdict with a confidence score [0.0, 1.0].
  """
  @spec evaluate_connect(any(), any(), attrs()) :: result()
  def evaluate_connect(_user, _org, attrs) when is_map(attrs) do
    # Default permissive stub with high confidence; wire real engine here.
    {:ok, %{verdict: :allow, score: 0.95, rationale: "default-allow (stub)"}}
  end
end

