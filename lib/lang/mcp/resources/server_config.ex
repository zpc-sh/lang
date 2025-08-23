defmodule Lang.MCP.Resources.ServerConfig do
  @moduledoc """
  Ash resource for MCP server configurations.

  Manages the configuration data for MCP servers including server types,
  connection parameters, user permissions, and operational settings.
  This resource integrates with ash_json_api to provide JSON-LD endpoints.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    domain: nil

  postgres do
    table("mcp_server_configs")
    repo(Lang.Repo)
  end

  json_api do
    type("mcp_server_config")
    includes([:user, :organization])

    routes do
      base("/api/v2/mcp/configs")
      get(:read)
      index(:read)
      post(:create)
      patch(:update)
      delete(:destroy)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      description("Human-readable name for the MCP server configuration")
    end

    attribute :server_type, :atom do
      allow_nil?(false)
      constraints(one_of: [:filesystem, :git, :database, :web_search, :code_analysis])
      description("Type of MCP server (filesystem, git, database, etc.)")
    end

    attribute :config, :map do
      allow_nil?(false)
      default(%{})
      description("Server-specific configuration parameters (JSON-LD compatible)")
    end

    attribute :enabled, :boolean do
      allow_nil?(false)
      default(true)
      description("Whether this configuration is active and can be used")
    end

    attribute :description, :string do
      description("Optional description of what this configuration is for")
    end

    attribute :tags, {:array, :string} do
      default([])
      description("Tags for organizing and filtering configurations")
    end

    attribute :connection_limits, :map do
      allow_nil?(false)

      default(%{
        "max_connections" => 5,
        "idle_timeout_seconds" => 900,
        "request_timeout_seconds" => 30
      })

      description("Connection limits and timeout settings")
    end

    attribute :security_settings, :map do
      allow_nil?(false)

      default(%{
        "allowed_operations" => ["read"],
        "max_request_size" => 1_048_576,
        "max_response_size" => 10_485_760,
        "rate_limit_per_hour" => 1000
      })

      description("Security restrictions and rate limits")
    end

    attribute :metadata, :map do
      default(%{})
      description("Additional metadata for JSON-LD context and versioning")
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Lang.Accounts.User do
      description("User who owns this configuration")
      allow_nil?(false)
      public?(true)
    end

    belongs_to :organization, Lang.Accounts.Organization do
      description("Organization this configuration belongs to")
      allow_nil?(true)
      public?(true)
    end

    has_many :connections, Lang.MCP.Resources.Connection do
      description("Active connections using this configuration")
      public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([
        :name,
        :server_type,
        :config,
        :enabled,
        :description,
        :tags,
        :connection_limits,
        :security_settings,
        :metadata,
        :user_id,
        :organization_id
      ])

      change(set_attribute(:metadata, &__MODULE__.build_json_ld_metadata/1))
    end

    update :update do
      accept([
        :name,
        :config,
        :enabled,
        :description,
        :tags,
        :connection_limits,
        :security_settings,
        :metadata
      ])

      change(set_attribute(:metadata, &__MODULE__.update_json_ld_metadata/1))
    end

    read :by_user_and_type do
      argument(:user_id, :uuid, allow_nil?: false)
      argument(:server_type, :atom, allow_nil?: false)

      filter(expr(user_id == ^arg(:user_id) and server_type == ^arg(:server_type)))
    end

    read :by_organization do
      argument(:organization_id, :uuid, allow_nil?: false)

      filter(expr(organization_id == ^arg(:organization_id)))
    end

    read :enabled_only do
      filter(expr(enabled == true))
    end
  end

  # Policies will be added after the MCP domain and authorizers are finalized

  validations do
    validate compare(:name, greater_than: 0, message: "Name cannot be empty") do
      where(changing(:name))
    end

    validate attribute_does_not_equal(:server_type, :invalid) do
      message("Server type must be valid")
    end

    # Custom validations will be added once MCP config is finalized
  end

  # Resource-level changes/preparations can be added once MCP domain is finalized

  # JSON-LD metadata builders

  defp build_json_ld_metadata(_changeset) do
    %{
      "@context" => "https://lang.nocsi.com/schema/v1/mcp-server-config",
      "@type" => "MCPServerConfiguration",
      "version" => "1.0.0",
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "schema_version" => "v1"
    }
  end

  defp update_json_ld_metadata(changeset) do
    existing_metadata = Ash.Changeset.get_attribute(changeset, :metadata) || %{}

    Map.merge(existing_metadata, %{
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "version" => increment_version(Map.get(existing_metadata, "version", "1.0.0"))
    })
  end

  defp increment_version(version) do
    case String.split(version, ".") do
      [major, minor, patch] ->
        patch_int = String.to_integer(patch) + 1
        "#{major}.#{minor}.#{patch_int}"

      _ ->
        "1.0.1"
    end
  end

  # Helper functions for common configurations

  def filesystem_config(root_path, opts \\ []) do
    %{
      "root_path" => root_path,
      "allowed_extensions" =>
        Keyword.get(opts, :allowed_extensions, [
          ".txt",
          ".md",
          ".json",
          ".yaml",
          ".yml",
          ".js",
          ".ts",
          ".py",
          ".ex",
          ".rs"
        ]),
      "max_file_size" => Keyword.get(opts, :max_file_size, 1_048_576),
      "read_only" => Keyword.get(opts, :read_only, false)
    }
  end

  def git_config(repository_url, opts \\ []) do
    %{
      "repository_url" => repository_url,
      "default_branch" => Keyword.get(opts, :default_branch, "main"),
      "clone_depth" => Keyword.get(opts, :clone_depth, 1),
      "allowed_operations" => Keyword.get(opts, :allowed_operations, ["read", "status", "log"])
    }
  end

  def database_config(connection_string, opts \\ []) do
    %{
      "connection_string" => connection_string,
      "read_only" => Keyword.get(opts, :read_only, true),
      "query_timeout" => Keyword.get(opts, :query_timeout, 30),
      "max_rows" => Keyword.get(opts, :max_rows, 1000),
      "allowed_schemas" => Keyword.get(opts, :allowed_schemas, [])
    }
  end

  def web_search_config(opts \\ []) do
    %{
      "search_engine" => Keyword.get(opts, :search_engine, "duckduckgo"),
      "max_results" => Keyword.get(opts, :max_results, 10),
      "safe_search" => Keyword.get(opts, :safe_search, true),
      "allowed_domains" => Keyword.get(opts, :allowed_domains, []),
      "blocked_domains" => Keyword.get(opts, :blocked_domains, [])
    }
  end

  def code_analysis_config(opts \\ []) do
    %{
      "supported_languages" =>
        Keyword.get(opts, :supported_languages, [
          "elixir",
          "rust",
          "javascript",
          "typescript",
          "python",
          "go"
        ]),
      "analysis_types" =>
        Keyword.get(opts, :analysis_types, [
          "syntax",
          "lint",
          "security",
          "complexity"
        ]),
      "max_file_size" => Keyword.get(opts, :max_file_size, 1_048_576)
    }
  end
end

defmodule Lang.MCP.Resources.ServerConfig.Validations do
  @moduledoc false
  # Ash validation callbacks should be arity-2 and return :ok | {:error, term}
  def validate_config_for_server_type(_changeset_or_record, _opts), do: :ok
  def validate_security_settings(_changeset_or_record, _opts), do: :ok
end

defmodule Lang.MCP.Resources.ServerConfig.Changes do
  @moduledoc false
  # Ash change callbacks should return {:ok, changeset} | {:error, term}
  def sanitize_config(changeset), do: {:ok, changeset}
  def sanitize_config(changeset, _opts), do: {:ok, changeset}
  def sanitize_config(changeset, _opts, _ctx), do: {:ok, changeset}

  def validate_connection_limits(changeset), do: {:ok, changeset}
  def validate_connection_limits(changeset, _opts), do: {:ok, changeset}
  def validate_connection_limits(changeset, _opts, _ctx), do: {:ok, changeset}
end

defmodule Lang.MCP.Resources.ServerConfig.Preparations do
  @moduledoc false
  # Preparation should return a query as-is for now
  def add_json_ld_context(query), do: query
  def add_json_ld_context(query, _opts), do: query
  def add_json_ld_context(query, _opts, _ctx), do: query
end
