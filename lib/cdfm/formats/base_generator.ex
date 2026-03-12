defmodule CDFM.Formats.BaseGenerator do
  @moduledoc """
  Base behaviour and utilities for format generators.

  Each format generator must implement this behaviour to generate
  format-specific code from Ash resource definitions.
  """

  @doc """
  Generates format-specific code from a blueprint resource definition.

  Returns a map containing the generated files and metadata.
  """
  @callback generate(blueprint :: map(), opts :: keyword()) ::
              {:ok, %{files: list(), metadata: map()}} | {:error, String.t()}

  @doc """
  Validates that a blueprint is compatible with this format.
  """
  @callback validate_blueprint(blueprint :: map()) :: :ok | {:error, String.t()}

  @doc """
  Returns format-specific installation requirements.
  """
  @callback installation_requirements() :: map()

  @doc """
  Returns format metadata including supported features.
  """
  @callback format_metadata() :: map()

  @doc """
  Returns the format identifier atom.
  """
  @callback format_name() :: atom()

  defmacro __using__(_opts) do
    quote do
      @behaviour CDFM.Formats.BaseGenerator

      import CDFM.Formats.BaseGenerator

      def validate_blueprint(blueprint) do
        with :ok <- validate_required_fields(blueprint),
             :ok <- validate_format_compatibility(blueprint) do
          :ok
        end
      end

      defp validate_required_fields(blueprint) do
        required_fields = [:module_name, :attributes, :relationships, :actions, :meta]

        case check_required_fields(blueprint, required_fields) do
          :ok -> :ok
          {:error, missing} -> {:error, "Missing required fields: #{inspect(missing)}"}
        end
      end

      defp validate_format_compatibility(blueprint) do
        available_formats = Map.get(blueprint, :available_formats, [:phoenix_html])

        if format_name() in available_formats do
          :ok
        else
          {:error, "Blueprint does not support #{format_name()} format"}
        end
      end

      defoverridable validate_blueprint: 1
    end
  end

  @doc """
  Utility function to check required fields in a blueprint.
  """
  def check_required_fields(blueprint, required_fields) do
    missing_fields = required_fields -- Map.keys(blueprint)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, missing_fields}
    end
  end

  @doc """
  Generates a file struct for the generated output.
  """
  def generate_file(path, content, opts \\ []) do
    %{
      path: path,
      content: content,
      type: Keyword.get(opts, :type, :code),
      mode: Keyword.get(opts, :mode, :create),
      description: Keyword.get(opts, :description, "Generated file")
    }
  end

  @doc """
  Extracts resource name from module name.
  """
  def extract_resource_name(module_name) when is_binary(module_name) do
    module_name
    |> String.split(".")
    |> List.last()
  end

  @doc """
  Generates a table name from resource name.
  """
  def generate_table_name(resource_name) do
    resource_name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/, "_")
    |> Kernel.<>("s")
  end

  @doc """
  Converts attribute type to format-specific type.
  """
  def map_attribute_type(ash_type, format) do
    case {ash_type, format} do
      {:string, :phoenix_html} -> "text"
      {:integer, :phoenix_html} -> "number"
      {:boolean, :phoenix_html} -> "checkbox"
      {:decimal, :phoenix_html} -> "number"
      {:date, :phoenix_html} -> "date"
      {:datetime, :phoenix_html} -> "datetime-local"
      {:uuid, :phoenix_html} -> "text"
      {:string, :terminal_ui} -> :text
      {:integer, :terminal_ui} -> :number
      {:boolean, :terminal_ui} -> :toggle
      {:decimal, :terminal_ui} -> :number
      {:date, :terminal_ui} -> :date
      {:datetime, :terminal_ui} -> :datetime
      {:uuid, :terminal_ui} -> :text
      {:string, :rest_api} -> "string"
      {:integer, :rest_api} -> "integer"
      {:boolean, :rest_api} -> "boolean"
      {:decimal, :rest_api} -> "number"
      {:date, :rest_api} -> "string"
      {:datetime, :rest_api} -> "string"
      {:uuid, :rest_api} -> "string"
      {type, _} -> to_string(type)
    end
  end

  @doc """
  Generates installation summary for a format.
  """
  def generate_installation_summary(blueprint, format, target_domain) do
    resource_name = extract_resource_name(blueprint[:module_name])

    %{
      format: format,
      target_module: "#{target_domain}.#{resource_name}",
      resource_name: resource_name,
      attribute_count: length(blueprint[:attributes] || []),
      relationship_count: length(blueprint[:relationships] || []),
      custom_action_count: length(blueprint[:actions] || []),
      estimated_complexity: calculate_complexity(blueprint),
      generated_files: estimate_generated_files(blueprint, format)
    }
  end

  @doc """
  Calculates complexity score for a blueprint.
  """
  def calculate_complexity(blueprint) do
    attribute_count = length(blueprint[:attributes] || [])
    relationship_count = length(blueprint[:relationships] || [])
    action_count = length(blueprint[:actions] || [])
    validation_count = length(blueprint[:validations] || [])

    total_elements = attribute_count + relationship_count + action_count + validation_count

    cond do
      total_elements <= 5 -> :simple
      total_elements <= 15 -> :moderate
      total_elements <= 30 -> :complex
      true -> :very_complex
    end
  end

  @doc """
  Estimates generated files for a format.
  """
  def estimate_generated_files(blueprint, format) do
    resource_name = extract_resource_name(blueprint[:module_name])
    base_files = ["#{String.downcase(resource_name)}.ex"]

    case format do
      :phoenix_html ->
        base_files ++
          [
            "#{String.downcase(resource_name)}_live.ex",
            "#{String.downcase(resource_name)}_live.html.heex",
            "#{String.downcase(resource_name)}_form_component.ex"
          ]

      :terminal_ui ->
        base_files ++
          [
            "#{String.downcase(resource_name)}_app.ex",
            "#{String.downcase(resource_name)}_view.ex"
          ]

      :rest_api ->
        base_files ++
          [
            "#{String.downcase(resource_name)}_controller.ex",
            "#{String.downcase(resource_name)}_view.ex"
          ]

      :admin_panel ->
        base_files ++
          [
            "#{String.downcase(resource_name)}_admin.ex"
          ]

      _ ->
        base_files
    end
  end

  @doc """
  Generates format-specific configuration.
  """
  def generate_format_config(format, blueprint, opts \\ []) do
    base_config = %{
      format: format,
      generated_at: DateTime.utc_now(),
      blueprint_version: blueprint[:version],
      generator_version: "1.0.0"
    }

    format_specific =
      case format do
        :phoenix_html ->
          %{
            live_view_version: "~> 1.1",
            uses_components: true,
            theme_support: true
          }

        :terminal_ui ->
          %{
            raxol_version: "~> 0.1",
            keyboard_navigation: true,
            ascii_charts: true
          }

        :rest_api ->
          %{
            json_api_version: "~> 1.0",
            openapi_spec: true,
            authentication: true
          }

        _ ->
          %{}
      end

    Map.merge(base_config, format_specific)
  end

  @doc """
  Validates format-specific options.
  """
  def validate_format_options(format, opts) do
    case format do
      :phoenix_html ->
        validate_phoenix_html_options(opts)

      :terminal_ui ->
        validate_terminal_ui_options(opts)

      :rest_api ->
        validate_rest_api_options(opts)

      _ ->
        :ok
    end
  end

  defp validate_phoenix_html_options(_opts), do: :ok
  defp validate_terminal_ui_options(_opts), do: :ok
  defp validate_rest_api_options(_opts), do: :ok
end
