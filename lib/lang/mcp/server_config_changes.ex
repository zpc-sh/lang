defmodule Lang.MCP.ServerConfig.Changes do
  @moduledoc false

  # Ash change callbacks should return {:ok, changeset} | {:error, term}
  def sanitize_config(changeset), do: {:ok, changeset}
  def sanitize_config(changeset, _opts), do: {:ok, changeset}
  def sanitize_config(changeset, _opts, _ctx), do: {:ok, changeset}

  def validate_connection_limits(changeset), do: {:ok, changeset}
  def validate_connection_limits(changeset, _opts), do: {:ok, changeset}
  def validate_connection_limits(changeset, _opts, _ctx), do: {:ok, changeset}
end
