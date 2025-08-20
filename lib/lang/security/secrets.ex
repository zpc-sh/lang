defmodule Lang.Security.Secrets do
  @moduledoc """
  Centralized secret management for LANG application.

  This module provides secure access to environment variables and secrets,
  with proper error handling and warnings for missing configuration.
  """

  require Logger

  @doc """
  Get the secret key base for Phoenix sessions and signing.
  This is required for the application to start.
  """
  def secret_key_base do
    get_required_env!("SECRET_KEY_BASE", """
    You must set SECRET_KEY_BASE in your environment.
    Generate a secure key with: mix phx.gen.secret
    """)
  end

  @doc """
  Get the LiveView signing salt.
  This is required for LiveView functionality.
  """
  def live_view_signing_salt do
    get_required_env!("LIVE_VIEW_SIGNING_SALT", """
    You must set LIVE_VIEW_SIGNING_SALT in your environment.
    Generate a secure salt with: mix phx.gen.secret 32
    """)
  end

  @doc """
  Get AshAuthentication signing secret.
  This is required for JWT token signing.
  """
  def ash_authentication_secret do
    get_required_env!("ASH_AUTHENTICATION_SECRET", """
    You must set ASH_AUTHENTICATION_SECRET in your environment.
    Generate a secure secret with: mix phx.gen.secret 64
    This is used for JWT token signing and other authentication operations.
    """)
  end

  @doc """
  Get database URL with fallback to individual components.
  """
  def database_url do
    case System.get_env("DATABASE_URL") do
      nil ->
        Logger.warning("DATABASE_URL not set, using individual database environment variables")
        nil

      url ->
        url
    end
  end

  @doc """
  Get database configuration from environment variables.
  """
  def database_config do
    %{
      username: get_env("DB_USERNAME", "postgres"),
      password: get_env("DB_PASSWORD", "postgres"),
      hostname: get_env("DB_HOSTNAME", "localhost"),
      database: get_env("DB_DATABASE", "lang_#{Mix.env()}"),
      port: get_env_integer("DB_PORT", 5432),
      pool_size: get_env_integer("DB_POOL_SIZE", 10)
    }
  end

  @doc """
  Get Redis configuration for caching.
  """
  def redis_url do
    get_env("REDIS_URL", "redis://localhost:6379/0")
  end

  @doc """
  Get application host configuration.
  """
  def app_host do
    get_env("APP_HOST", "localhost")
  end

  @doc """
  Get application port configuration.
  """
  def app_port do
    get_env_integer("PORT", 4000)
  end

  @doc """
  Get LSP server port configuration.
  """
  def lsp_port do
    get_env_integer("LSP_PORT", 4001)
  end

  @doc """
  Get encryption key for sensitive data storage.
  This is used for encrypting PII and other sensitive information.
  """
  def encryption_key do
    get_required_env!("ENCRYPTION_KEY", """
    You must set ENCRYPTION_KEY in your environment.
    Generate a secure key with: :crypto.strong_rand_bytes(32) |> Base.encode64()
    This key is used for encrypting sensitive data in the database.
    """)
  end

  @doc """
  Get API rate limiting configuration.
  """
  def rate_limit_config do
    %{
      enabled: get_env_boolean("RATE_LIMITING_ENABLED", true),
      requests_per_minute: get_env_integer("RATE_LIMIT_RPM", 60),
      burst_limit: get_env_integer("RATE_LIMIT_BURST", 10),
      cleanup_interval: get_env_integer("RATE_LIMIT_CLEANUP_INTERVAL", 60_000)
    }
  end

  @doc """
  Get CORS configuration.
  """
  def cors_config do
    allowed_origins =
      case get_env("CORS_ALLOWED_ORIGINS") do
        nil -> ["http://localhost:3000", "http://localhost:4000"]
        origins -> String.split(origins, ",") |> Enum.map(&String.trim/1)
      end

    %{
      enabled: get_env_boolean("CORS_ENABLED", true),
      allowed_origins: allowed_origins,
      allowed_methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
      allowed_headers: [
        "Authorization",
        "Content-Type",
        "Accept",
        "Origin",
        "User-Agent",
        "Cache-Control"
      ]
    }
  end

  @doc """
  Get text processing limits configuration.
  """
  def text_processing_limits do
    %{
      # 50MB
      max_content_size: get_env_integer("MAX_CONTENT_SIZE", 50 * 1024 * 1024),
      # 30 seconds
      analysis_timeout: get_env_integer("ANALYSIS_TIMEOUT", 30_000),
      max_conversation_turns: get_env_integer("MAX_CONVERSATION_TURNS", 1000),
      max_timeline_states: get_env_integer("MAX_TIMELINE_STATES", 10_000)
    }
  end

  @doc """
  Get monitoring and telemetry configuration.
  """
  def telemetry_config do
    %{
      enabled: get_env_boolean("TELEMETRY_ENABLED", true),
      prometheus_enabled: get_env_boolean("PROMETHEUS_ENABLED", false),
      metrics_port: get_env_integer("METRICS_PORT", 9090),
      log_level: get_env_atom("LOG_LEVEL", :info),
      structured_logging: get_env_boolean("STRUCTURED_LOGGING", false)
    }
  end

  @doc """
  Get external service configuration.
  """
  def external_services_config do
    %{
      # OpenAI/AI services
      openai_api_key: get_env("OPENAI_API_KEY"),
      anthropic_api_key: get_env("ANTHROPIC_API_KEY"),

      # Webhooks
      webhook_secret: get_env("WEBHOOK_SECRET"),

      # Email service
      sendgrid_api_key: get_env("SENDGRID_API_KEY"),

      # File storage
      aws_access_key_id: get_env("AWS_ACCESS_KEY_ID"),
      aws_secret_access_key: get_env("AWS_SECRET_ACCESS_KEY"),
      s3_bucket: get_env("S3_BUCKET"),
      s3_region: get_env("S3_REGION", "us-east-1")
    }
  end

  @doc """
  Validate that all required secrets are present on application start.
  Call this during application initialization to fail fast on missing config.
  """
  def validate_required_secrets! do
    Logger.info("Validating required secrets and environment variables...")

    try do
      # Required secrets that must be present
      _secret_key = secret_key_base()
      _lv_salt = live_view_signing_salt()
      _auth_secret = ash_authentication_secret()
      _enc_key = encryption_key()

      Logger.info("All required secrets are configured ✓")
      :ok
    rescue
      e in RuntimeError ->
        Logger.error("Missing required secrets: #{e.message}")
        System.halt(1)
    end
  end

  @doc """
  Check if we're running in production mode.
  """
  def production? do
    Mix.env() == :prod
  end

  @doc """
  Check if we're running in development mode.
  """
  def development? do
    Mix.env() == :dev
  end

  @doc """
  Check if we're running in test mode.
  """
  def test? do
    Mix.env() == :test
  end

  # Private helper functions

  defp get_required_env!(env_var, error_message) do
    case System.get_env(env_var) do
      nil ->
        raise RuntimeError, """
        Missing required environment variable: #{env_var}

        #{error_message}
        """

      "" ->
        raise RuntimeError, """
        Environment variable #{env_var} is empty.

        #{error_message}
        """

      value ->
        value
    end
  end

  defp get_env(env_var, default \\ nil) do
    case System.get_env(env_var) do
      nil ->
        if default == nil do
          Logger.warning("Environment variable #{env_var} not set")
        end

        default

      value ->
        value
    end
  end

  defp get_env_integer(env_var, default) do
    case get_env(env_var) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {int, ""} ->
            int

          _ ->
            Logger.warning(
              "Invalid integer value for #{env_var}: #{value}, using default: #{default}"
            )

            default
        end
    end
  end

  defp get_env_boolean(env_var, default) do
    case get_env(env_var) do
      nil ->
        default

      value ->
        case String.downcase(value) do
          "true" ->
            true

          "false" ->
            false

          "1" ->
            true

          "0" ->
            false

          "yes" ->
            true

          "no" ->
            false

          _ ->
            Logger.warning(
              "Invalid boolean value for #{env_var}: #{value}, using default: #{default}"
            )

            default
        end
    end
  end

  defp get_env_atom(env_var, default) do
    case get_env(env_var) do
      nil ->
        default

      value ->
        try do
          String.to_existing_atom(value)
        rescue
          ArgumentError ->
            Logger.warning(
              "Invalid atom value for #{env_var}: #{value}, using default: #{default}"
            )

            default
        end
    end
  end
end
