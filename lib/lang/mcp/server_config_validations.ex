defmodule Lang.MCP.ServerConfig.Validations do
  @moduledoc false

  # Ash validation callbacks should be arity-2 and return :ok | {:error, term}
  def validate_config_for_server_type(_changeset_or_record, _opts), do: :ok
  def validate_security_settings(_changeset_or_record, _opts), do: :ok

  # Metadata helpers split out from ServerConfig
  def build_json_ld_metadata(_changeset_or_record) do
    %{
      "@context" => "https://lang.nocsi.com/schema/v1/mcp-server-config",
      "@type" => "MCPServerConfig",
      "version" => "1.0.0",
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "schema_version" => "v1"
    }
  end

  def update_json_ld_metadata(changeset_or_record) do
    existing = get_metadata(changeset_or_record)

    Map.merge(existing, %{
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp get_metadata(%Ash.Changeset{} = changeset) do
    Ash.Changeset.get_attribute(changeset, :metadata) || %{}
  end

  defp get_metadata(%{metadata: meta}) when is_map(meta), do: meta
  defp get_metadata(_), do: %{}
end
