defmodule Nullity.CDFM.Spec do
  @moduledoc """
  Spec structs and helpers for Nullity's CDFM-style, spec-driven generation.

  This module is deliberately framework-agnostic so we can extract it into
  a library later without changes.
  """

  @typedoc "Canonical LSP method specification"
  @type method_spec :: %__MODULE__.Method{
          id: String.t(),
          name: String.t(),
          category: String.t() | nil,
          description: String.t() | nil,
          priority: String.t() | nil,
          spec_status: String.t() | nil,
          impl_file: String.t() | nil,
          impl_module: String.t() | nil,
          impl_function: atom() | nil,
          impl_arity: non_neg_integer() | nil,
          params_schema: map() | nil,
          result_schema: map() | nil,
          metadata: map(),
          links: map()
        }

  defmodule Method do
    @enforce_keys [:id, :name]
    defstruct [
      :id,
      :name,
      :category,
      :description,
      :priority,
      :spec_status,
      :impl_file,
      :impl_module,
      :impl_function,
      :impl_arity,
      :params_schema,
      :result_schema,
      metadata: %{},
      links: %{}
    ]
  end

  @doc """
  Derive a category from a method name like "lang.think.explain_intent" => "think".
  """
  def derive_category(name) when is_binary(name) do
    case String.split(name, ".") do
      ["lang", cat | _] -> cat
      [cat | _] -> cat
      _ -> nil
    end
  end

  @doc """
  Normalize a raw map (from JSON/YAML) into a %Method{} struct.
  """
  def normalize_method(raw, ctx \\ %{}) when is_map(raw) do
    # Merge any method-local @context with inherited ctx
    ctx =
      case raw["@context"] || raw[:"@context"] do
        %{} = local -> Map.merge(ctx, local)
        _ -> ctx
      end
    id = raw["@id"] || raw[:id]
    name_from_id = normalize_id_to_name(id, ctx)
    short_name = raw["name"] || raw[:name] || ""
    name = cond do
      is_binary(name_from_id) and name_from_id != "" -> name_from_id
      String.contains?(short_name, ".") -> short_name
      true -> short_name
    end

    impl = raw["implementation"] || raw[:implementation] || %{}
    impl_module = raw["module"] || raw[:module] || impl["impl_module"] || impl[:impl_module]
    impl_file = impl["file"] || impl[:file] || impl["impl_file"] || impl[:impl_file]
    impl_function = impl["function"] || impl[:function] || impl["impl_function"] || impl[:impl_function]
    impl_arity = impl["arity"] || impl[:arity] || impl["impl_arity"] || impl[:impl_arity]

    %Method{
      id: id || name,
      name: name,
      category: raw["category"] || raw[:category] || derive_category(name),
      description: raw["description"] || raw[:description],
      priority: (impl["priority"] || raw["priority"] || raw[:priority]) |> normalize_priority(),
      spec_status: impl["status"] || raw["spec_status"] || raw[:spec_status],
      impl_file: impl_file || default_impl_file(name),
      impl_module: impl_module,
      impl_function: to_atom_maybe(impl_function) || :handle,
      impl_arity: impl_arity || 2,
      params_schema: raw["params_schema"] || raw[:params_schema] || build_params_schema(raw),
      result_schema: raw["result_schema"] || raw[:result_schema] || build_result_schema(raw),
      metadata:
        (raw["metadata"] || raw[:metadata] || %{})
        |> Map.merge(Map.take(impl, ["track", :track, "dependencies", :dependencies]) |> stringify_keys()),
      links: raw["links"] || raw[:links] || %{}
    }
  end

  @doc """
  Parse JSON-LD content (as binary) into a list of %Method{}.

  Note: This is a minimal parser; for now we accept either a map or a list of maps.
  """
  def parse_jsonld!(binary_or_term) do
    term = if is_binary(binary_or_term), do: Jason.decode!(binary_or_term), else: binary_or_term

    ctx =
      if is_map(term) do
        term["@context"] || term[:"@context"] || %{}
      else
        %{}
      end

    cond do
      is_list(term) -> Enum.map(term, &normalize_method(&1, ctx))
      is_map(term) -> [normalize_method(term, ctx)]
      true -> raise ArgumentError, "Invalid JSON-LD content"
    end
  end

  @doc """
  Parse content in either JSON or YAML (if available) into method specs.

  If it looks like JSON, uses Jason. Otherwise, attempts to parse YAML if
  :yamerl_constr is available. Raises if neither succeeds.
  """
  def parse_spec!(content) when is_binary(content) do
    trimmed = String.trim_leading(content)
    cond do
      String.starts_with?(trimmed, ["{", "["]) -> parse_jsonld!(content)
      true -> parse_yaml!(content)
    end
  end

  defp parse_yaml!(content) do
    if Code.ensure_loaded?(:yamerl_constr) do
      # :yamerl returns Erlang terms; convert to Elixir with atomized keys cautiously
      [doc | _] = :yamerl_constr.string(String.to_charlist(content))
      term = yaml_to_elixir(doc)
      parse_jsonld!(term)
    else
      raise "YAML parser (:yamerl_constr) not available; add :yamerl to deps or provide JSON"
    end
  rescue
    _ -> raise "Failed to parse YAML content"
  end

  defp yaml_to_elixir(term) when is_list(term) do
    Enum.map(term, &yaml_to_elixir/1)
  end

  defp yaml_to_elixir(term) when is_map(term) do
    term
    |> Enum.map(fn {k, v} -> {to_string(k), yaml_to_elixir(v)} end)
    |> Enum.into(%{})
  end

  defp yaml_to_elixir(term) when is_binary(term) or is_number(term) or is_boolean(term), do: term
  defp yaml_to_elixir(term) when is_atom(term), do: Atom.to_string(term)
  defp yaml_to_elixir(other), do: other

  defp normalize_id_to_name(nil, _ctx), do: nil
  defp normalize_id_to_name(id, ctx) when is_binary(id) do
    cond do
      String.starts_with?(id, "http") and String.contains?(id, "#") ->
        String.split(id, "#") |> List.last()
      String.contains?(id, ":") ->
        # compact IRI, e.g., "lang:agent.spawn"
        [prefix, rest] = String.split(id, ":", parts: 2)
        _iri = Map.get(ctx, prefix) || Map.get(ctx, String.to_atom(prefix))
        # Return as dot-name with lang prefix
        if prefix in ["lang", :lang], do: "lang." <> rest, else: rest
      true -> id
    end
  end

  defp default_impl_file(name) when is_binary(name) do
    cat = derive_category(name) || "other"
    snake = name |> String.replace(".", "_") |> String.downcase()
    "lib/lang/lsp/#{cat}/#{snake}.ex"
  end

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.into(%{})
  end

  defp to_atom_maybe(nil), do: nil
  defp to_atom_maybe(v) when is_atom(v), do: v
  defp to_atom_maybe(v) when is_binary(v), do: String.to_atom(v)

  defp normalize_priority(nil), do: nil
  defp normalize_priority(p) when is_binary(p) do
    case String.downcase(p) do
      "critical" -> "Critical"
      "high" -> "High"
      "medium" -> "Medium"
      "low" -> "Low"
      other -> other
    end
  end

  # Build schemas from JSON-LD parameters/returns blocks if present
  defp build_params_schema(raw) do
    params = raw["parameters"] || raw[:parameters]
    if is_list(params) do
      props =
        params
        |> Enum.map(fn p ->
          name = p["name"] || p[:name]
          t = map_xsd_type(p["dataType"] || p[:dataType])
          {name, Map.merge(%{"type" => t}, default_for(p))}
        end)
        |> Enum.into(%{})

      required =
        params
        |> Enum.filter(&(!!(&1["required"] || &1[:required])))
        |> Enum.map(&(&1["name"] || &1[:name]))

      schema = %{"type" => "object", "properties" => props}
      if required == [], do: schema, else: Map.put(schema, "required", required)
    else
      nil
    end
  end

  defp default_for(p) do
    case p["default"] || p[:default] do
      nil -> %{}
      v -> %{"default" => v}
    end
  end

  defp build_result_schema(raw) do
    returns = raw["returns"] || raw[:returns]
    if is_map(returns) do
      success = returns["success"] || returns[:success]
      error = returns["error"] || returns[:error]

      schemas = []
      schemas =
        if is_map(success) do
          [schema_from_kv(success) | schemas]
        else
          schemas
        end

      schemas =
        if is_map(error) do
          [schema_from_kv(error) | schemas]
        else
          schemas
        end

      if schemas == [], do: nil, else: %{"oneOf" => Enum.reverse(schemas)}
    else
      nil
    end
  end

  defp schema_from_kv(%{"schema" => kv} = _spec) when is_map(kv) do
    props =
      kv
      |> Enum.map(fn {k, v} -> {k, %{"type" => map_xsd_type(v)}} end)
      |> Enum.into(%{})

    %{"type" => "object", "properties" => props}
  end
  defp schema_from_kv(_), do: %{"type" => "object"}

  defp map_xsd_type(nil), do: "object"
  defp map_xsd_type(t) when is_binary(t) do
    case String.downcase(t) do
      "xsd:string" -> "string"
      "xsd:boolean" -> "boolean"
      "xsd:integer" -> "integer"
      "xsd:number" -> "number"
      "xsd:float" -> "number"
      "xsd:double" -> "number"
      "xsd:array" -> "array"
      "xsd:object" -> "object"
      "string" -> "string"
      "boolean" -> "boolean"
      "integer" -> "integer"
      "number" -> "number"
      "array" -> "array"
      "object" -> "object"
      _ -> "string"
    end
  end
end
