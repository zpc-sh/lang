defmodule Elixir.Lang.LSP.Lang.Lang.Generate.FromDiagram do
  @moduledoc "Architecture diagram → boilerplate"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.generate.from_diagram"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    diagram_content = Map.get(params, "diagram")
    diagram_type = Map.get(params, "type", "mermaid")
    target_language = Map.get(params, "language", "elixir")
    options = Map.get(params, "options", %{})

    case diagram_content do
      nil ->
        {:error, "diagram content is required"}

      diagram when is_binary(diagram) ->
        case generate_code_from_diagram(diagram, diagram_type, target_language, options) do
          {:ok, generated_code} ->
            {:ok,
             %{
               generated_code: generated_code,
               diagram_type: diagram_type,
               language: target_language,
               metadata: %{
                 lines_generated: count_lines(generated_code),
                 timestamp: DateTime.utc_now()
               }
             }}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, "diagram must be a string"}
    end
  end

  defp generate_code_from_diagram(diagram, type, language, options) do
    case type do
      "mermaid" ->
        generate_from_mermaid(diagram, language, options)

      "plantuml" ->
        generate_from_plantuml(diagram, language, options)

      "flowchart" ->
        generate_from_flowchart(diagram, language, options)

      _ ->
        {:error, "unsupported diagram type: #{type}"}
    end
  end

  defp generate_from_mermaid(diagram, language, options) do
    # Parse mermaid diagram and extract entities/relationships
    entities = extract_mermaid_entities(diagram)

    case language do
      "elixir" ->
        generate_elixir_from_entities(entities, options)

      "phoenix" ->
        generate_phoenix_from_entities(entities, options)

      "rust" ->
        generate_rust_from_entities(entities, options)

      _ ->
        {:error, "unsupported target language: #{language}"}
    end
  end

  defp generate_from_plantuml(diagram, language, _options) do
    # Basic PlantUML parsing - look for class definitions
    class_matches = Regex.scan(~r/class\s+(\w+)\s*\{([^}]*)\}/i, diagram)

    case language do
      "elixir" ->
        modules =
          Enum.map(class_matches, fn [_, name, body] ->
            fields = extract_fields_from_class_body(body)
            generate_elixir_module(name, fields)
          end)

        {:ok, Enum.join(modules, "\n\n")}

      _ ->
        {:error, "PlantUML generation only supports Elixir currently"}
    end
  end

  defp generate_from_flowchart(diagram, language, _options) do
    # Basic flowchart parsing
    steps = extract_flowchart_steps(diagram)

    case language do
      "elixir" ->
        {:ok, generate_elixir_pipeline(steps)}

      _ ->
        {:error, "Flowchart generation only supports Elixir currently"}
    end
  end

  defp extract_mermaid_entities(diagram) do
    # Extract entity definitions from mermaid syntax
    # Look for patterns like: EntityName { field1 type1, field2 type2 }
    entity_pattern = ~r/(\w+)\s*\{\s*([^}]*)\s*\}/

    Regex.scan(entity_pattern, diagram)
    |> Enum.map(fn [_, name, fields_str] ->
      fields = parse_field_definitions(fields_str)
      %{name: name, fields: fields}
    end)
  end

  defp parse_field_definitions(fields_str) do
    fields_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn field ->
      case String.split(field) do
        [name, type] -> %{name: name, type: type}
        [name] -> %{name: name, type: "string"}
        _ -> %{name: field, type: "string"}
      end
    end)
  end

  defp extract_fields_from_class_body(body) do
    body
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      case String.split(line, ":") do
        [name, type] -> %{name: String.trim(name), type: String.trim(type)}
        _ -> %{name: line, type: "string"}
      end
    end)
  end

  defp extract_flowchart_steps(diagram) do
    # Simple step extraction - look for step definitions
    step_pattern = ~r/(\w+)\[([^\]]+)\]/

    Regex.scan(step_pattern, diagram)
    |> Enum.map(fn [_, id, description] ->
      %{id: id, description: description}
    end)
  end

  defp generate_elixir_from_entities(entities, options) do
    use_ash = Map.get(options, "use_ash", false)

    modules =
      Enum.map(entities, fn entity ->
        if use_ash do
          generate_ash_resource(entity)
        else
          generate_elixir_struct(entity)
        end
      end)

    {:ok, Enum.join(modules, "\n\n")}
  end

  defp generate_phoenix_from_entities(entities, options) do
    include_liveview = Map.get(options, "include_liveview", true)

    code_parts = []

    # Generate schemas
    schemas = Enum.map(entities, &generate_phoenix_schema/1)
    code_parts = code_parts ++ schemas

    # Generate controllers
    controllers = Enum.map(entities, &generate_phoenix_controller/1)
    code_parts = code_parts ++ controllers

    # Generate LiveViews if requested
    if include_liveview do
      liveviews = Enum.map(entities, &generate_phoenix_liveview/1)
      code_parts = code_parts ++ liveviews
    end

    {:ok, Enum.join(code_parts, "\n\n")}
  end

  defp generate_rust_from_entities(entities, _options) do
    structs = Enum.map(entities, &generate_rust_struct/1)
    {:ok, Enum.join(structs, "\n\n")}
  end

  defp generate_elixir_module(name, fields) do
    """
    defmodule #{String.capitalize(name)} do
      @moduledoc "Generated from diagram"

      defstruct [#{format_struct_fields(fields)}]

      def new(attrs \\ %{}) do
        struct(__MODULE__, attrs)
      end
    end
    """
  end

  defp generate_elixir_struct(entity) do
    """
    defmodule #{String.capitalize(entity.name)} do
      @moduledoc "Generated from diagram"

      defstruct [#{format_struct_fields(entity.fields)}]

      def new(attrs \\ %{}) do
        struct(__MODULE__, attrs)
      end

      def changeset(struct, params) do
        # Add validation logic here
        struct
        |> Map.merge(params)
      end
    end
    """
  end

  defp generate_ash_resource(entity) do
    """
    defmodule #{String.capitalize(entity.name)} do
      @moduledoc "Generated Ash resource from diagram"

      use Ash.Resource, data_layer: Ash.DataLayer.Ets

      attributes do
    #{format_ash_attributes(entity.fields)}
      end

      actions do
        defaults [:create, :read, :update, :destroy]
      end
    end
    """
  end

  defp generate_phoenix_schema(entity) do
    """
    defmodule MyApp.#{String.capitalize(entity.name)} do
      @moduledoc "Generated Phoenix schema from diagram"

      use Ecto.Schema
      import Ecto.Changeset

      schema "#{String.downcase(entity.name)}s" do
    #{format_ecto_fields(entity.fields)}

        timestamps()
      end

      def changeset(#{String.downcase(entity.name)}, attrs) do
        #{String.downcase(entity.name)}
        |> cast(attrs, [#{format_field_names(entity.fields)}])
        |> validate_required([#{format_required_fields(entity.fields)}])
      end
    end
    """
  end

  defp generate_phoenix_controller(entity) do
    resource_name = String.downcase(entity.name)
    module_name = String.capitalize(entity.name)

    """
    defmodule MyAppWeb.#{module_name}Controller do
      @moduledoc "Generated Phoenix controller from diagram"

      use MyAppWeb, :controller
      alias MyApp.#{module_name}

      def index(conn, _params) do
        #{resource_name}s = list_#{resource_name}s()
        render(conn, :index, #{resource_name}s: #{resource_name}s)
      end

      def show(conn, %{"id" => id}) do
        #{resource_name} = get_#{resource_name}!(id)
        render(conn, :show, #{resource_name}: #{resource_name})
      end

      def create(conn, %{"#{resource_name}" => #{resource_name}_params}) do
        case create_#{resource_name}(#{resource_name}_params) do
          {:ok, #{resource_name}} ->
            conn
            |> put_status(:created)
            |> render(:show, #{resource_name}: #{resource_name})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(:errors, changeset: changeset)
        end
      end

      defp list_#{resource_name}s, do: []  # Implement your logic
      defp get_#{resource_name}!(id), do: %#{module_name}{id: id}  # Implement your logic
      defp create_#{resource_name}(params), do: {:ok, %#{module_name}{}}  # Implement your logic
    end
    """
  end

  defp generate_phoenix_liveview(entity) do
    resource_name = String.downcase(entity.name)
    module_name = String.capitalize(entity.name)

    """
    defmodule MyAppWeb.#{module_name}Live do
      @moduledoc "Generated Phoenix LiveView from diagram"

      use MyAppWeb, :live_view

      def mount(_params, _session, socket) do
        {:ok, assign(socket, #{resource_name}s: list_#{resource_name}s())}
      end

      def render(assigns) do
        ~H\"\"\"
        <div class="mx-auto max-w-4xl">
          <h1 class="text-2xl font-bold"><%= "#{module_name}s" %></h1>

          <div class="mt-4 grid gap-4">
            <div :for={#{resource_name} <- @#{resource_name}s} class="border rounded p-4">
              <%= inspect(#{resource_name}) %>
            </div>
          </div>
        </div>
        \"\"\"
      end

      defp list_#{resource_name}s, do: []  # Implement your logic
    end
    """
  end

  defp generate_rust_struct(entity) do
    """
    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    pub struct #{String.capitalize(entity.name)} {
    #{format_rust_fields(entity.fields)}
    }

    impl #{String.capitalize(entity.name)} {
        pub fn new() -> Self {
            Self {
    #{format_rust_default_values(entity.fields)}
            }
        }
    }
    """
  end

  defp generate_elixir_pipeline(steps) do
    step_functions =
      Enum.map(steps, fn step ->
        """
        defp #{step.id}(data) do
          # #{step.description}
          data
        end
        """
      end)

    pipeline_chain =
      steps
      |> Enum.map(& &1.id)
      |> Enum.join(" |> ")

    """
    defmodule GeneratedPipeline do
      @moduledoc "Generated pipeline from flowchart"

      def process(data) do
        data
        |> #{pipeline_chain}
      end

    #{Enum.join(step_functions, "\n")}
    end
    """
  end

  # Helper functions for formatting
  defp format_struct_fields(fields) do
    fields
    |> Enum.map(fn field -> ":#{field.name}" end)
    |> Enum.join(", ")
  end

  defp format_ash_attributes(fields) do
    fields
    |> Enum.map(fn field ->
      ash_type = elixir_type_to_ash_type(field.type)
      "    attribute :#{field.name}, :#{ash_type}"
    end)
    |> Enum.join("\n")
  end

  defp format_ecto_fields(fields) do
    fields
    |> Enum.map(fn field ->
      ecto_type = elixir_type_to_ecto_type(field.type)
      "    field :#{field.name}, :#{ecto_type}"
    end)
    |> Enum.join("\n")
  end

  defp format_field_names(fields) do
    fields
    |> Enum.map(fn field -> ":#{field.name}" end)
    |> Enum.join(", ")
  end

  defp format_required_fields(fields) do
    # Assume all fields are required for now
    format_field_names(fields)
  end

  defp format_rust_fields(fields) do
    fields
    |> Enum.map(fn field ->
      rust_type = elixir_type_to_rust_type(field.type)
      "    pub #{field.name}: #{rust_type},"
    end)
    |> Enum.join("\n")
  end

  defp format_rust_default_values(fields) do
    fields
    |> Enum.map(fn field ->
      default_value = rust_default_value(field.type)
      "                #{field.name}: #{default_value},"
    end)
    |> Enum.join("\n")
  end

  # Type conversion helpers
  defp elixir_type_to_ash_type(type) do
    case String.downcase(type) do
      "string" -> "string"
      "integer" -> "integer"
      "boolean" -> "boolean"
      "float" -> "float"
      "datetime" -> "utc_datetime"
      _ -> "string"
    end
  end

  defp elixir_type_to_ecto_type(type) do
    case String.downcase(type) do
      "string" -> "string"
      "integer" -> "integer"
      "boolean" -> "boolean"
      "float" -> "float"
      "datetime" -> "utc_datetime"
      _ -> "string"
    end
  end

  defp elixir_type_to_rust_type(type) do
    case String.downcase(type) do
      "string" -> "String"
      "integer" -> "i64"
      "boolean" -> "bool"
      "float" -> "f64"
      "datetime" -> "chrono::DateTime<chrono::Utc>"
      _ -> "String"
    end
  end

  defp rust_default_value(type) do
    case String.downcase(type) do
      "string" -> "String::new()"
      "integer" -> "0"
      "boolean" -> "false"
      "float" -> "0.0"
      "datetime" -> "chrono::Utc::now()"
      _ -> "String::new()"
    end
  end

  defp count_lines(code) do
    code
    |> String.split("\n")
    |> length()
  end
end
