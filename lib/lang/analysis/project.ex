defmodule Lang.Analysis.Project do
  use Ecto.Schema
  import Ecto.Changeset

  alias Lang.Analysis.{AnalysisSession, ProjectRuleConfig}
  alias Lang.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @project_types ~w(web_app mobile_app api_service microservice desktop_app library cli_tool)
  @statuses ~w(active archived paused)

  schema "projects" do
    field :name, :string
    field :description, :string
    field :repository_url, :string
    field :language, :string
    field :framework, :string
    field :project_type, :string, default: "web_app"
    field :status, :string, default: "active"
    field :settings, :map, default: %{}

    belongs_to :user, User
    has_many :analysis_sessions, AnalysisSession, on_delete: :delete_all
    has_many :project_rule_configs, ProjectRuleConfig, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for project creation.
  """
  def create_changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :description,
      :repository_url,
      :language,
      :framework,
      :project_type,
      :settings,
      :user_id
    ])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_inclusion(:project_type, @project_types)
    |> validate_format(:repository_url, ~r/^https?:\/\//, message: "must be a valid HTTP URL")
    |> validate_settings()
    |> unique_constraint([:user_id, :name], message: "Project name already exists")
  end

  @doc """
  Creates a changeset for project updates.
  """
  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :description,
      :repository_url,
      :language,
      :framework,
      :project_type,
      :status,
      :settings
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_inclusion(:project_type, @project_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:repository_url, ~r/^https?:\/\//, message: "must be a valid HTTP URL")
    |> validate_settings()
    |> unique_constraint([:user_id, :name], message: "Project name already exists")
  end

  @doc """
  Creates a changeset for archiving a project.
  """
  def archive_changeset(project) do
    change(project, status: "archived")
  end

  @doc """
  Creates a changeset for activating a project.
  """
  def activate_changeset(project) do
    change(project, status: "active")
  end

  # Private functions

  defp validate_settings(changeset) do
    case get_field(changeset, :settings) do
      nil ->
        changeset

      settings when is_map(settings) ->
        validate_settings_structure(changeset, settings)

      _ ->
        add_error(changeset, :settings, "must be a valid JSON object")
    end
  end

  defp validate_settings_structure(changeset, settings) do
    # Define valid setting keys and their types
    valid_keys = %{
      "max_file_size_mb" => &is_integer/1,
      "excluded_extensions" => &is_list/1,
      "excluded_paths" => &is_list/1,
      "analysis_timeout_minutes" => &is_integer/1,
      "enable_security_rules" => &is_boolean/1,
      "enable_performance_rules" => &is_boolean/1,
      "enable_style_rules" => &is_boolean/1,
      "custom_rules" => &is_list/1,
      "notification_settings" => &is_map/1
    }

    errors =
      settings
      |> Enum.reduce([], fn {key, value}, acc ->
        case Map.get(valid_keys, key) do
          nil ->
            acc

          validator when is_function(validator) ->
            if validator.(value) do
              acc
            else
              ["Invalid value for setting '#{key}'" | acc]
            end
        end
      end)

    case errors do
      [] ->
        validate_settings_values(changeset, settings)

      errors ->
        Enum.reduce(errors, changeset, fn error, acc ->
          add_error(acc, :settings, error)
        end)
    end
  end

  defp validate_settings_values(changeset, settings) do
    changeset
    |> validate_max_file_size(Map.get(settings, "max_file_size_mb"))
    |> validate_timeout(Map.get(settings, "analysis_timeout_minutes"))
    |> validate_excluded_extensions(Map.get(settings, "excluded_extensions"))
    |> validate_excluded_paths(Map.get(settings, "excluded_paths"))
  end

  defp validate_max_file_size(changeset, nil), do: changeset

  defp validate_max_file_size(changeset, size)
       when is_integer(size) and size > 0 and size <= 1000 do
    changeset
  end

  defp validate_max_file_size(changeset, _) do
    add_error(changeset, :settings, "max_file_size_mb must be between 1 and 1000")
  end

  defp validate_timeout(changeset, nil), do: changeset

  defp validate_timeout(changeset, timeout)
       when is_integer(timeout) and timeout > 0 and timeout <= 120 do
    changeset
  end

  defp validate_timeout(changeset, _) do
    add_error(changeset, :settings, "analysis_timeout_minutes must be between 1 and 120")
  end

  defp validate_excluded_extensions(changeset, nil), do: changeset

  defp validate_excluded_extensions(changeset, extensions) when is_list(extensions) do
    valid_extensions =
      extensions
      |> Enum.all?(fn ext ->
        is_binary(ext) and String.starts_with?(ext, ".") and String.length(ext) > 1
      end)

    if valid_extensions do
      changeset
    else
      add_error(
        changeset,
        :settings,
        "excluded_extensions must be a list of file extensions starting with '.'"
      )
    end
  end

  defp validate_excluded_extensions(changeset, _) do
    add_error(changeset, :settings, "excluded_extensions must be a list")
  end

  defp validate_excluded_paths(changeset, nil), do: changeset

  defp validate_excluded_paths(changeset, paths) when is_list(paths) do
    valid_paths = Enum.all?(paths, &is_binary/1)

    if valid_paths do
      changeset
    else
      add_error(changeset, :settings, "excluded_paths must be a list of strings")
    end
  end

  defp validate_excluded_paths(changeset, _) do
    add_error(changeset, :settings, "excluded_paths must be a list")
  end

  @doc """
  Returns the default settings for a new project.
  """
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

  @doc """
  Returns all valid project types.
  """
  def project_types, do: @project_types

  @doc """
  Returns all valid statuses.
  """
  def statuses, do: @statuses

  @doc """
  Checks if the project is active.
  """
  def active?(%__MODULE__{status: "active"}), do: true
  def active?(_), do: false

  @doc """
  Checks if the project is archived.
  """
  def archived?(%__MODULE__{status: "archived"}), do: true
  def archived?(_), do: false
end
