defmodule Lang.Spatial.Workers.MapBuilderWorker do
  @moduledoc """
  Builds/refreshes a Spatial.Map snapshot from FSScanner + analyses.
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3
  require Logger

  alias Lang.Spatial.Map
  alias Lang.Native.FSScanner

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id} = args}) do
    case args do
      %{"path" => path} when is_binary(path) ->
        case FSScanner.scan(path, max_depth: 8) do
          {:ok, %{stats: fs}} ->
            languages = Map.get(fs, :files_by_extension, %{})

            {symbols, relations} = build_symbols_and_relations(path)
            symbols = augment_symbols_with_treesitter(path, symbols)
            relations = augment_relations_with_treesitter(path, relations)

            graph = %{
              symbols: symbols,
              relations: relations,
              owners: %{},
              root: path
            }

            stats = %{
              files: Map.get(fs, :total_files, 0),
              directories: Map.get(fs, :total_directories, 0),
              languages: languages,
              generated_at: DateTime.utc_now()
            }

            _ = Map.create(%{project_id: project_id, graph_summary: graph, stats: stats})
            :ok

          {:error, :timeout} ->
            _ = Map.create(%{project_id: project_id, graph_summary: %{}, stats: %{generated_at: DateTime.utc_now(), error: :timeout}})
            :ok

          _ ->
            _ = Map.create(%{project_id: project_id, graph_summary: %{}, stats: %{generated_at: DateTime.utc_now()}})
            :ok
        end

      _ ->
        # No path provided, create an empty snapshot
        _ = Map.create(%{project_id: project_id, graph_summary: %{}, stats: %{generated_at: DateTime.utc_now()}})
        :ok
    end
  end
  end

  # Build a compact symbol table and trivial relations using native FSScanner searches
  defp build_symbols_and_relations(root_path) do
    symbols = %{}
    relations = []

    {symbols, relations} =
      Enum.reduce(symbol_search_specs(), {symbols, relations}, fn {label, pattern}, {sym_acc, rel_acc} ->
        case FSScanner.search(root_path, pattern, max_results: 10_000, context_lines: 0) do
          {:ok, results} when is_list(results) ->
            Enum.reduce(results, {sym_acc, rel_acc}, fn res, {sacc, racc} ->
              file = extract_file_path(res)
              line = extract_line_number(res)
              text = extract_line_text(res)

              case extract_symbol(text, label) do
                nil -> {sacc, racc}
                {kind, name} ->
                  entry = %{kind: kind, name: name, line: line}
                  {Map.update(sacc, file, [entry], fn list -> [entry | list] end), racc}
              end
            end)

          _ -> {sym_acc, rel_acc}
        end
      end)

    relations =
      Enum.reduce(relation_search_specs(), relations, fn {rel_type, pattern}, acc ->
        case FSScanner.search(root_path, pattern, max_results: 10_000, context_lines: 0) do
          {:ok, results} when is_list(results) ->
            Enum.reduce(results, acc, fn res, racc ->
              file = extract_file_path(res)
              line = extract_line_number(res)
              text = extract_line_text(res)

              case extract_relation_target(text, rel_type) do
                nil -> racc
                target ->
                  lang = infer_language_from_path(file)
                  target_kind = classify_relation_target(lang, rel_type, target)
                  [%{type: rel_type, from: file, to: target, line: line, language: lang, target_kind: target_kind} | racc]
              end
            end)

          _ -> acc
        end
      end)

    symbols = for {k, v} <- symbols, into: %{}, do: {k, Enum.uniq_by(v, &{&1.kind, &1.name, &1.line})}
    relations = Enum.uniq_by(relations, &{&1.type, &1.from, &1.to, &1.line})
    {symbols, relations}
  end

  # Use tree-sitter queries (via native FSScanner) to enrich symbol table
  defp augment_symbols_with_treesitter(root_path, symbols) when is_binary(root_path) and is_map(symbols) do
    ts_queries = Lang.Native.FSScanner.tree_sitter_queries()

    Enum.reduce(ts_queries, symbols, fn {language, groups}, sym_acc ->
      Enum.reduce(groups, sym_acc, fn {group_name, pattern}, acc2 ->
        lang = to_string(language)

        case Lang.Native.FSScanner.search_code(root_path, lang, pattern, max_results: 10_000) do
          {:ok, results} when is_list(results) ->
            Enum.reduce(results, acc2, fn res, acc ->
              file = extract_file_path(res)
              line = extract_line_number(res)
              name = extract_ts_captured_name(res) || infer_name_from_text(extract_line_text(res))
              kind = ts_group_to_kind(group_name)
              entry = %{kind: kind, name: name, line: line, language: lang, ts: true}
              Map.update(acc, file, [entry], fn list -> [entry | list] end)
            end)

          _ -> acc2
        end
      end)
    end)
    |> then(fn sym -> for {k, v} <- sym, into: %{}, do: {k, Enum.uniq_by(v, &{&1.kind, &1.name, &1.line})} end)
  rescue
    _ -> symbols
  end

  defp augment_symbols_with_treesitter(_root_path, symbols), do: symbols

  # Use tree-sitter queries to add imports/exports/uses relations where supported
  defp augment_relations_with_treesitter(root_path, relations) when is_binary(root_path) and is_list(relations) do
    ts_queries = Lang.Native.FSScanner.tree_sitter_queries()

    rels =
      Enum.reduce(ts_queries, relations, fn {language, groups}, acc ->
        lang = to_string(language)

        acc =
          case Map.get(groups, :imports) do
            nil -> acc
            pattern ->
              case Lang.Native.FSScanner.search_code(root_path, lang, pattern, max_results: 10_000) do
                {:ok, results} when is_list(results) ->
                  Enum.reduce(results, acc, fn res, racc ->
                    file = extract_file_path(res)
                    line = extract_line_number(res)
                    target = extract_ts_captured_name(res) || infer_name_from_text(extract_line_text(res))
                    if is_nil(target) do
                      racc
                    else
                      target_kind = classify_relation_target(lang, :import, target)
                      [%{type: :import, from: file, to: target, line: line, language: lang, ts: true, target_kind: target_kind} | racc]
                    end
                  end)

                _ -> acc
              end
          end

        acc =
          case Map.get(groups, :exports) do
            nil -> acc
            pattern ->
              case Lang.Native.FSScanner.search_code(root_path, lang, pattern, max_results: 10_000) do
                {:ok, results} when is_list(results) ->
                  Enum.reduce(results, acc, fn res, racc ->
                    file = extract_file_path(res)
                    line = extract_line_number(res)
                    name = extract_ts_captured_name(res) || infer_name_from_text(extract_line_text(res)) || "default"
                    target_kind = classify_relation_target(lang, :export, name)
                    [%{type: :export, from: file, to: name, line: line, language: lang, ts: true, target_kind: target_kind} | racc]
                  end)

                _ -> acc
              end
          end

        acc =
          case Map.get(groups, :use_statements) do
            nil -> acc
            pattern ->
              case Lang.Native.FSScanner.search_code(root_path, lang, pattern, max_results: 10_000) do
                {:ok, results} when is_list(results) ->
                  Enum.reduce(results, acc, fn res, racc ->
                    file = extract_file_path(res)
                    line = extract_line_number(res)
                    target = extract_ts_captured_name(res) || infer_name_from_text(extract_line_text(res))
                    if is_nil(target) do
                      racc
                    else
                      target_kind = classify_relation_target(lang, :use, target)
                      [%{type: :use, from: file, to: target, line: line, language: lang, ts: true, target_kind: target_kind} | racc]
                    end
                  end)

                _ -> acc
              end
          end

        acc
      end)

    Enum.uniq_by(rels, &{&1.type, &1.from, &1.to, &1.line})
  rescue
    _ -> relations
  end

  defp augment_relations_with_treesitter(_root_path, relations), do: relations

  # Basic language-agnostic symbol searches by keyword; extraction refines names
  defp symbol_search_specs do
    [
      {:elixir_module, ~S(defmodule\s+\S+)},
      {:elixir_fn, ~S(\bdefp?\s+\S+)},
      {:rust_fn, ~S(\bfn\s+\S+)},
      {:rust_struct, ~S(\bstruct\s+\S+)},
      {:rust_enum, ~S(\benum\s+\S+)},
      {:js_fn, ~S(\bfunction\s+\S+)},
      {:js_class, ~S(\bclass\s+\S+)},
      {:py_def, ~S(\bdef\s+\S+)},
      {:py_class, ~S(\bclass\s+\S+)}
    ]
  end

  # Trivial relation searches for imports/uses/requires
  defp relation_search_specs do
    [
      {:imports, ~S(\bimport\s+.*?from\s+['\"][^'\"]+['\"]|\brequire\(\s*['\"][^'\"]+['\"]\s*\))},
      {:uses, ~S(\buse\s+[A-Za-z0-9_\.]+)},
      {:aliases, ~S(\balias\s+[A-Za-z0-9_\.]+)},
      {:py_imports, ~S(\bfrom\s+[\w\.]+\s+import\b|\bimport\s+[\w\.]+)},
      {:rust_uses, ~S(\buse\s+[A-Za-z0-9_:]+)}
    ]
  end

  defp extract_symbol(line_text, label) when is_binary(line_text) do
    case label do
      :elixir_module ->
        Regex.run(~r/defmodule\s+([A-Za-z0-9_\.]+)/, line_text, capture: :all_but_first)
        |> to_symbol(:module)

      :elixir_fn ->
        Regex.run(~r/defp?\s+([a-z_][\w\!\?@]*)/, line_text, capture: :all_but_first)
        |> to_symbol(:function)

      :rust_fn ->
        Regex.run(~r/\bfn\s+([a-zA-Z_][\w]*)/, line_text, capture: :all_but_first)
        |> to_symbol(:function)

      :rust_struct ->
        Regex.run(~r/\bstruct\s+([A-Z][\w]*)/, line_text, capture: :all_but_first)
        |> to_symbol(:struct)

      :rust_enum ->
        Regex.run(~r/\benum\s+([A-Z][\w]*)/, line_text, capture: :all_but_first)
        |> to_symbol(:enum)

      :js_fn ->
        Regex.run(~r/\bfunction\s+([a-zA-Z_][\w]*)/, line_text, capture: :all_but_first)
        |> to_symbol(:function)

      :js_class ->
        Regex.run(~r/\bclass\s+([A-Z][\w]*)/, line_text, capture: :all_but_first)
        |> to_symbol(:class)

      :py_def ->
        Regex.run(~r/\bdef\s+([a-z_][\w]*)/, line_text, capture: :all_but_first)
        |> to_symbol(:function)

      :py_class ->
        Regex.run(~r/\bclass\s+([A-Z][\w]*)/, line_text, capture: :all_but_first)
        |> to_symbol(:class)

      _ ->
        nil
    end
  end

  defp extract_symbol(_, _), do: nil

  defp to_symbol(nil, _kind), do: nil
  defp to_symbol([name], kind), do: {kind, name}
  defp to_symbol(_, _), do: nil

  defp extract_relation_target(line_text, rel_type) when is_binary(line_text) do
    case rel_type do
      :imports ->
        case Regex.run(~r/(?:from\s+['\"]([^'\"]+)['\"]|require\(\s*['\"]([^'\"]+)['\"]\s*\))/, line_text, capture: :all_but_first) do
          [a, nil] when is_binary(a) -> a
          [nil, b] when is_binary(b) -> b
          [a, b] -> a || b
          _ -> nil
        end

      :py_imports ->
        case Regex.run(~r/(?:from\s+([\w\.]+)\s+import|import\s+([\w\.]+))/, line_text, capture: :all_but_first) do
          [a, nil] when is_binary(a) -> a
          [nil, b] when is_binary(b) -> b
          [a, b] -> a || b
          _ -> nil
        end

      :uses ->
        case Regex.run(~r/\buse\s+([A-Za-z0-9_\.]+)/, line_text, capture: :all_but_first) do
          [mod] -> mod
          _ -> nil
        end

      :aliases ->
        case Regex.run(~r/\balias\s+([A-Za-z0-9_\.]+)/, line_text, capture: :all_but_first) do
          [mod] -> mod
          _ -> nil
        end

      :rust_uses ->
        case Regex.run(~r/\buse\s+([A-Za-z0-9_:]+)/, line_text, capture: :all_but_first) do
          [path] -> path
          _ -> nil
        end

      _ -> nil
    end
  end

  defp extract_relation_target(_, _), do: nil

  defp extract_file_path(res) do
    Map.get(res, :file) || Map.get(res, :path) || Map.get(res, "file") || Map.get(res, "path") || "?"
  end

  defp extract_line_number(res) do
    case Map.get(res, :line_number) || Map.get(res, "line_number") || Map.get(res, :line) || Map.get(res, "line") do
      n when is_integer(n) -> n
      _ -> nil
    end
  end

  defp extract_line_text(res) do
    Map.get(res, :line_content) || Map.get(res, "line_content") || Map.get(res, :match) || Map.get(res, "match") || ""
  end

  defp extract_ts_captured_name(res) do
    # Try common shapes for captures returned by NIF
    case Map.get(res, :captures) || Map.get(res, "captures") do
      list when is_list(list) ->
        list
        |> Enum.find_value(fn cap ->
          Map.get(cap, :text) || Map.get(cap, "text") || Map.get(cap, :value) || Map.get(cap, "value")
        end)

      _ ->
        Map.get(res, :name) || Map.get(res, "name")
    end
  end

  defp infer_name_from_text(text) when is_binary(text) do
    # Best-effort fallback to extract an identifier from a code-like line
    case Regex.run(~r/([A-Za-z_][A-Za-z0-9_!?@]*)/, text, capture: :all_but_first) do
      [name] -> name
      _ -> nil
    end
  end

  defp infer_name_from_text(_), do: nil

  defp ts_group_to_kind(group) do
    case group do
      :functions -> :function
      :function -> :function
      :arrow_functions -> :function
      :classes -> :class
      :interfaces -> :interface
      :types -> :type
      :structs -> :struct
      :enums -> :enum
      :impls -> :impl
      :macros -> :macro
      _ -> :symbol
    end
  end

  # Try to infer source language from file extension
  defp infer_language_from_path(path) when is_binary(path) do
    case String.downcase(Path.extname(path)) do
      ".js" -> "javascript"
      ".jsx" -> "javascript"
      ".mjs" -> "javascript"
      ".ts" -> "typescript"
      ".tsx" -> "typescript"
      ".rs" -> "rust"
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".py" -> "python"
      _ -> nil
    end
  end

  defp infer_language_from_path(_), do: nil

  # Classify targets for language-specific relation grouping
  defp classify_relation_target(lang, rel_type, target) do
    case {lang, rel_type} do
      {lang, :import} when lang in ["javascript", "typescript"] ->
        if String.starts_with?(target, ["./", "../", "/"]) or String.ends_with?(target, [".js", ".mjs", ".ts", ".tsx", ".jsx"]) do
          :path
        else
          :module
        end

      {"rust", :use} ->
        :module_path

      {"elixir", rel} when rel in [:use, :aliases] ->
        :module

      {"python", :imports} ->
        :module

      {_lang, _rel} ->
        :unknown
    end
  end
end
