defmodule Nullity.CDFM.Validator do
  @moduledoc """
  Lightweight validations for LSP doc rows and normalized specs.

  Use for pre-ingest and CI gating.
  """

  alias Nullity.CDFM.Spec.Method

  @priorities ~w(Critical High Medium Low)

  @doc """
  Validate a parsed docs row map: %{method, status, priority, description, impl_file}.
  Returns a list of issue strings (empty if valid).
  """
  def validate_doc_row(%{method: m, status: s, priority: p, impl_file: f} = _row) do
    issues = []
    issues = if is_binary(m) and m != "", do: issues, else: ["missing method" | issues]

    issues =
      if s in ["implemented", "in_progress", "not_implemented"],
        do: issues,
        else: ["invalid status #{inspect(s)}" | issues]

    issues =
      if is_binary(p) and p in @priorities,
        do: issues,
        else: ["invalid priority #{inspect(p)}" | issues]

    issues = if is_binary(f) and f != "", do: issues, else: ["missing impl_file" | issues]
    issues
  end

  def validate_doc_row(_), do: ["invalid row shape"]

  @doc """
  Validate a normalized spec (Method struct).
  Returns a list of issue strings (empty if valid).
  """
  def validate_spec(%Method{} = s) do
    issues = []

    issues =
      if is_binary(s.name) and s.name != "", do: issues, else: ["spec missing name" | issues]

    issues =
      if is_binary(s.category) and s.category != "",
        do: issues,
        else: ["spec missing category (derived)" | issues]

    issues =
      if is_binary(s.impl_file) and s.impl_file != "",
        do: issues,
        else: ["spec missing impl_file (will be derived)" | issues]

    issues
  end

  def validate_spec(_), do: ["invalid spec shape"]
end
