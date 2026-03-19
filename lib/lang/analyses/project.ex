defmodule Lang.Analyses.Project do
  @moduledoc """
  Project Resource for Analysis Domain

  Represents a user's analysis project containing multiple analysis sessions.
  Projects organize related analysis work and maintain configuration settings
  for text intelligence processing.
  """

  use Ash.Resource,
    domain: Lang.Analyses,
    data_layer: AshPostgres.DataLayer

  alias Lang.Analyses.Run
  alias Lang.Accounts.User

  postgres do
    table("projects")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      constraints(min_length: 2, max_length: 100)
    end

    attribute :description, :string do
      allow_nil?(true)
      constraints(max_length: 1000)
    end

    attribute :repository_url, :string do
      allow_nil?(true)
      constraints(match: ~r/^https?:\/\//)
    end

    attribute :language, :string do
      allow_nil?(true)
    end

    attribute :framework, :string do
      allow_nil?(true)
    end

    attribute :project_type, :atom do
      allow_nil?(false)
      default(:web_app)

      constraints(
        one_of: [
          :web_app,
          :mobile_app,
          :api_service,
          :microservice,
          :desktop_app,
          :library,
          :cli_tool
        ]
      )
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:active)
      constraints(one_of: [:active, :archived, :paused])
    end

    attribute :settings, :map do
      allow_nil?(false)

      default(%{
        "max_file_size_mb" => 10,
        "excluded_extensions" => [".log", ".tmp", ".cache", ".DS_Store"],
        "excluded_paths" => ["node_modules", ".git", "build", "dist", "coverage"],
        "analysis_timeout_minutes" => 30,
        "enable_security_rules" => true,
        "enable_performance_rules" => true,
        "enable_style_rules" => false,
        "custom_rules" => [],
        "notification_settings" => %{
          "email_on_critical" => true,
          "email_on_completion" => false,
          "webhook_url" => nil
        }
      })
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :user, User do
      attribute_writable?(true)
    end

    has_many :analysis_sessions, Run do
      destination_attribute(:project_id)
    end
  end

  identities do
    identity :unique_name_per_user, [:user_id, :name] do
      message("Project name already exists for this user")
    end
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :name,
        :description,
        :repository_url,
        :language,
        :framework,
        :project_type,
        :settings,
        :user_id
      ])

      validate(present([:name, :user_id]))

      validate match(:repository_url, ~r/^https?:\/\//) do
        where(present(:repository_url))
        message("must be a valid HTTP URL")
      end

      change(fn changeset, _context ->
        settings = Ash.Changeset.get_attribute(changeset, :settings) || %{}
        validated_settings = validate_settings_structure(settings)
        Ash.Changeset.change_attribute(changeset, :settings, validated_settings)
      end)
    end

    update :update do
      accept([
        :name,
        :description,
        :repository_url,
        :language,
        :framework,
        :project_type,
        :status,
        :settings
      ])

      validate(present(:name))

      validate match(:repository_url, ~r/^https?:\/\//) do
        where(present(:repository_url))
        message("must be a valid HTTP URL")
      end

      change(fn changeset, _context ->
        case Ash.Changeset.get_change(changeset, :settings) do
          nil ->
            changeset

          settings ->
            validated_settings = validate_settings_structure(settings)
            Ash.Changeset.change_attribute(changeset, :settings, validated_settings)
        end
      end)
    end

    update :archive do
      accept([])
      change(set_attribute(:status, :archived))
    end

    update :activate do
      accept([])
      change(set_attribute(:status, :active))
    end

    destroy(:destroy)
  end

  code_interface do
    define(:read_all, action: :read)
    define(:by_id, action: :read, get_by: [:id])
    define(:create, action: :create)
    define(:update, action: :update)
    define(:archive, action: :archive)
    define(:activate, action: :activate)
    define(:destroy, action: :destroy)
  end

  preparations do
    prepare(build(load: [:analysis_sessions]))
  end

  # Helper functions for settings validation
  defp validate_settings_structure(settings) when is_map(settings) do
    valid_keys = %{
      "max_file_size_mb" => &validate_max_file_size/1,
      "excluded_extensions" => &validate_excluded_extensions/1,
      "excluded_paths" => &validate_excluded_paths/1,
      "analysis_timeout_minutes" => &validate_timeout/1,
      "enable_security_rules" => &is_boolean/1,
      "enable_performance_rules" => &is_boolean/1,
      "enable_style_rules" => &is_boolean/1,
      "custom_rules" => &is_list/1,
      "notification_settings" => &is_map/1
    }

    # Validate each setting
    validated_settings =
      settings
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        case Map.get(valid_keys, key) do
          # Allow unknown keys for now
          nil ->
            Map.put(acc, key, value)

          validator when is_function(validator) ->
            if validator.(value) do
              Map.put(acc, key, value)
            else
              # Skip invalid values, keep defaults
              acc
            end
        end
      end)

    # Merge with defaults to ensure all required keys exist
    Map.merge(default_settings(), validated_settings)
  end

  defp validate_settings_structure(_), do: default_settings()

  defp validate_max_file_size(size) when is_integer(size) and size > 0 and size <= 1000, do: true
  defp validate_max_file_size(_), do: false

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0 and timeout <= 120,
    do: true

  defp validate_timeout(_), do: false

  defp validate_excluded_extensions(extensions) when is_list(extensions) do
    Enum.all?(extensions, fn ext ->
      is_binary(ext) and String.starts_with?(ext, ".") and String.length(ext) > 1
    end)
  end

  defp validate_excluded_extensions(_), do: false

  defp validate_excluded_paths(paths) when is_list(paths) do
    Enum.all?(paths, &is_binary/1)
  end

  defp validate_excluded_paths(_), do: false

  def default_settings do
    %{
      "max_file_size_mb" => 10,
      "excluded_extensions" => [".log", ".tmp", ".cache", ".DS_Store"],
      "excluded_paths" => ["node_modules", ".git", "build", "dist", "coverage"],
      "analysis_timeout_minutes" => 30,
      "enable_security_rules" => true,
      "enable_performance_rules" => true,
      "enable_style_rules" => false,
      "custom_rules" => [],
      "notification_settings" => %{
        "email_on_critical" => true,
        "email_on_completion" => false,
        "webhook_url" => nil
      }
    }
  end

  # Computed attributes and helper functions
  def active?(%{status: :active}), do: true
  def active?(_), do: false

  def archived?(%{status: :archived}), do: true
  def archived?(_), do: false

  def project_types do
    [:web_app, :mobile_app, :api_service, :microservice, :desktop_app, :library, :cli_tool]
  end

  def statuses do
    [:active, :archived, :paused]
  end
end
