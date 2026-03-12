defmodule LangWeb.LspEditor.LspEditorLive do
  use LangWeb, :live_view

  alias Lang.Native.FSScanner
  alias Kyozo.Lang.UniversalParser.LinkedDataExtractor
  alias MarkdownLD.JSONLD
  alias Nullity.CDFM.Adapters.Store.Ash, as: SpecStore
  alias Phoenix.LiveView.JS

  @lsp_doc_path "docs/lsp.md"

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to file changes
      Phoenix.PubSub.subscribe(Lang.PubSub, "lsp_editor:file_changes")
      # Subscribe to implementation progress updates
      Phoenix.PubSub.subscribe(Lang.PubSub, "lsp_editor:progress")
    end

    socket =
      socket
      |> assign(:page_title, "LSP Master Tracker - First of Its Kind")
      |> assign(:loading, true)
      |> assign(:lsp_methods, [])
      |> assign(:categories, [])
      |> assign(:selected_category, "all")
      |> assign(:selected_priority, "all")
      |> assign(:search_query, "")
      |> assign(:editor_open, false)
      |> assign(:editing_file, nil)
      |> assign(:file_content, "")
      # :view or :table
      |> assign(:edit_mode, :view)
      |> assign(:raw_markdown, "")
      |> assign(:stats, %{total: 0, implemented: 0, in_progress: 0, not_started: 0})
      |> assign(:last_saved, nil)
      |> assign(:unsaved_changes, false)
      |> assign(:sticky_editor_open, false)
      |> assign(:editor_hosts_status, %{})
      |> assign(:markdown_ld_data, %{
        entities: [],
        relationships: [],
        triples: [],
        context: %{},
        confidence_scores: %{}
      })
      |> assign(:semantic_entities, [])
      |> assign(:semantic_entity_count, 0)
      |> assign(:semantic_summary, nil)
      |> assign(:jsonld_processing, false)

    {:ok, load_lsp_data(socket), temporary_assigns: [lsp_methods: []]}
  end

  @impl true
  def handle_event("editor_status", %{"engine" => engine} = params, socket) do
    host = Map.get(params, "host") || "unknown"
    statuses = Map.put(socket.assigns.editor_hosts_status || %{}, host, engine)
    {:noreply, assign(socket, :editor_hosts_status, statuses)}
  end

  def handle_params(params, _url, socket) do
    mode =
      case params["mode"] do
        "raw" -> :raw
        "tiptap" -> :tiptap
        "table" -> :table
        _ -> :view
      end

    socket =
      socket
      |> assign(:selected_category, params["category"] || "all")
      |> assign(:selected_priority, params["priority"] || "all")
      |> assign(:search_query, params["search"] || "")
      |> assign(:edit_mode, mode)
      |> apply_filters()

    {:noreply, socket}
  end

  def handle_event("toggle_edit_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_atom(mode)

    socket =
      socket
      |> assign(:edit_mode, mode_atom)
      |> push_patch(to: build_path(socket, %{mode: mode}))

    {:noreply, socket}
  end

  def handle_event("toggle_sticky_editor", _params, socket) do
    current_state = Map.get(socket.assigns, :sticky_editor_open, false)

    socket =
      socket
      |> assign(:sticky_editor_open, !current_state)

    {:noreply, socket}
  end

  def handle_event("filter_category", %{"category" => category}, socket) do
    socket =
      socket
      |> assign(:selected_category, category)
      |> apply_filters()
      |> push_patch(to: build_path(socket))

    {:noreply, socket}
  end

  def handle_event("filter_priority", %{"priority" => priority}, socket) do
    socket =
      socket
      |> assign(:selected_priority, priority)
      |> apply_filters()
      |> push_patch(to: build_path(socket))

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> apply_filters()
      |> push_patch(to: build_path(socket))

    {:noreply, socket}
  end

  def handle_event("update_status", %{"method" => method_name, "status" => new_status}, socket) do
    case update_method_status(method_name, new_status) do
      {:ok, _} ->
        # Broadcast the change to other connected clients
        Phoenix.PubSub.broadcast(
          Lang.PubSub,
          "lsp_editor:progress",
          {:method_updated, method_name, new_status}
        )

        socket =
          socket
          |> put_flash(:info, "Updated #{method_name} status to #{new_status}")
          |> assign(:unsaved_changes, false)
          |> assign(:last_saved, DateTime.utc_now())
          |> load_lsp_data()

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to update: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  def handle_event(
        "update_description",
        %{"method" => method_name, "description" => new_description},
        socket
      ) do
    case update_method_description(method_name, new_description) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Updated description for #{method_name}")
          |> assign(:unsaved_changes, false)
          |> assign(:last_saved, DateTime.utc_now())
          |> load_lsp_data()

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to update description: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  def handle_event(
        "update_priority",
        %{"method" => method_name, "priority" => new_priority},
        socket
      ) do
    case update_method_priority(method_name, new_priority) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Updated priority for #{method_name}")
          |> assign(:unsaved_changes, false)
          |> assign(:last_saved, DateTime.utc_now())
          |> load_lsp_data()

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to update priority: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  def handle_event("open_file", %{"file_path" => file_path}, socket) do
    case read_implementation_file(file_path) do
      {:ok, content} ->
        socket =
          socket
          |> assign(:editor_open, false)
          |> assign(:editing_file, file_path)
          |> assign(:file_content, content)
          |> assign(:sticky_editor_open, true)

        {:noreply, socket}

      {:error, :file_not_found} ->
        # Create stub file
        case create_stub_file(file_path) do
          {:ok, content} ->
            socket =
              socket
              |> assign(:editor_open, false)
              |> assign(:editing_file, file_path)
              |> assign(:file_content, content)
              |> assign(:sticky_editor_open, true)
              |> put_flash(:info, "Created stub file: #{file_path}")

            {:noreply, socket}

          {:error, reason} ->
            socket = put_flash(socket, :error, "Failed to create file: #{inspect(reason)}")
            {:noreply, socket}
        end

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to open file: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  def handle_event("save_file", %{"content" => content}, socket) do
    case socket.assigns.editing_file do
      nil ->
        {:noreply, put_flash(socket, :error, "No file selected for editing")}

      file_path ->
        case write_file(file_path, content) do
          :ok ->
            socket =
              socket
              |> assign(:file_content, content)
              |> assign(:last_saved, DateTime.utc_now())
              |> put_flash(:info, "Saved #{file_path}")

            {:noreply, socket}

          {:error, reason} ->
            socket = put_flash(socket, :error, "Failed to save: #{inspect(reason)}")
            {:noreply, socket}
        end
    end
  end

  def handle_event("open_file_modal", %{"file_path" => file_path}, socket) do
    case read_implementation_file(file_path) do
      {:ok, content} ->
        socket =
          socket
          |> assign(:editor_open, true)
          |> assign(:sticky_editor_open, false)
          |> assign(:editing_file, file_path)
          |> assign(:file_content, content)

        {:noreply, socket}

      {:error, :file_not_found} ->
        case create_stub_file(file_path) do
          {:ok, content} ->
            socket =
              socket
              |> assign(:editor_open, true)
              |> assign(:sticky_editor_open, false)
              |> assign(:editing_file, file_path)
              |> assign(:file_content, content)
              |> put_flash(:info, "Created stub file: #{file_path}")

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to create file: #{inspect(reason)}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to open file: #{inspect(reason)}")}
    end
  end

  def handle_event("close_editor", _params, socket) do
    socket =
      socket
      |> assign(:editor_open, false)
      |> assign(:editing_file, nil)
      |> assign(:file_content, "")

    {:noreply, socket}
  end

  def handle_event("reload_lsp", _params, socket) do
    socket =
      socket
      |> put_flash(:info, "Reloading LSP documentation...")
      |> load_lsp_data()

    {:noreply, socket}
  end

  def handle_event("save_all_changes", _params, socket) do
    content = socket.assigns.raw_markdown

    case save_markdown_changes(content) do
      :ok ->
        socket =
          socket
          |> assign(:unsaved_changes, false)
          |> assign(:last_saved, DateTime.utc_now())
          |> put_flash(:info, "All changes saved successfully")
          |> load_lsp_data()
          |> apply_filters()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save changes: #{reason}")}
    end
  end

  def handle_event("export_csv", _params, socket) do
    csv_content = export_to_csv(socket.assigns.lsp_methods)

    socket =
      socket
      |> put_flash(:info, "CSV export generated")
      |> push_event("download_csv", %{
        content: csv_content,
        filename: "lsp_methods_#{Date.utc_today()}.csv"
      })

    {:noreply, socket}
  end

  def handle_event("bulk_update_status", %{"from" => from_status, "to" => to_status}, socket) do
    count = bulk_update_method_status(from_status, to_status)

    socket =
      socket
      |> put_flash(:info, "Updated #{count} methods from #{from_status} to #{to_status}")
      |> assign(:last_saved, DateTime.utc_now())
      |> load_lsp_data()

    {:noreply, socket}
  end

  def handle_event("add_method", %{"method" => method_data}, socket) do
    case add_new_method(method_data) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Added new method: #{method_data["method"]}")
          |> assign(:last_saved, DateTime.utc_now())
          |> load_lsp_data()

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to add method: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  def handle_event("delete_method", %{"method" => method_name}, socket) do
    case delete_method(method_name) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Deleted method: #{method_name}")
          |> assign(:last_saved, DateTime.utc_now())
          |> load_lsp_data()

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to delete method: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  def handle_event("update_file_content", %{"content" => content}, socket) do
    socket = assign(socket, :file_content, content)
    {:noreply, socket}
  end

  def handle_event("format_file", %{"content" => content}, socket) do
    # For now, just return the content as-is
    # In a full implementation, this would call `mix format` on the content
    socket =
      socket
      |> assign(:file_content, content)
      |> put_flash(:info, "File formatted (placeholder)")

    {:noreply, socket}
  end

  def handle_event("update_raw_markdown", %{"content" => content}, socket) do
    socket =
      socket
      |> assign(:raw_markdown, content)
      |> assign(:unsaved_changes, true)
      |> process_markdown_ld_async(content)

    {:noreply, socket}
  end

  def handle_event(
        "update_semantic_data",
        %{"entities" => entities, "entity_count" => count},
        socket
      ) do
    # Enhanced semantic data processing
    enhanced_entities = enhance_entities_with_jsonld(entities, socket.assigns.markdown_ld_data)

    socket =
      socket
      |> assign(:semantic_entities, enhanced_entities)
      |> assign(:semantic_entity_count, count)
      |> update_method_semantic_confidence(enhanced_entities)
      |> put_flash(:info, "Found #{count} semantic entities with JSON-LD enhancement")

    {:noreply, socket}
  end

  def handle_event("show_semantic_summary", summary, socket) do
    socket =
      socket
      |> assign(:semantic_summary, summary)
      |> put_flash(
        :info,
        "Semantic Summary: #{summary["total_entities"]} entities, #{summary["lsp_methods"]} methods"
      )

    {:noreply, socket}
  end

  def handle_info({:method_updated, method_name, new_status}, socket) do
    socket =
      socket
      |> put_flash(:info, "#{method_name} updated to #{new_status}")
      |> load_lsp_data()

    {:noreply, socket}
  end

  def handle_info({:markdown_ld_processed, linked_data}, socket) do
    socket =
      socket
      |> assign(:markdown_ld_data, linked_data)
      |> assign(:jsonld_processing, false)
      |> enhance_methods_with_linked_data(linked_data)
      |> put_flash(
        :info,
        "JSON-LD processing complete: #{length(linked_data.entities)} entities found"
      )

    {:noreply, socket}
  end

  def handle_info({:markdown_ld_error, reason}, socket) do
    socket =
      socket
      |> assign(:jsonld_processing, false)
      |> put_flash(:error, "JSON-LD processing failed: #{inspect(reason)}")

    {:noreply, socket}
  end

  def handle_info({:file_changed, @lsp_doc_path}, socket) do
    socket =
      socket
      |> put_flash(:info, "LSP documentation updated externally")
      |> load_lsp_data()

    {:noreply, socket}
  end

  # Private functions

  defp load_lsp_data(socket) do
    case SpecStore.read_all_methods() do
      {:ok, methods} ->
        model_methods = Enum.map(methods, &model_to_lv/1)
        categories = extract_categories(model_methods)
        stats = calculate_stats(model_methods)

        socket
        |> assign(:lsp_methods, model_methods)
        |> assign(:categories, categories)
        |> assign(:raw_markdown, "")
        |> assign(:markdown_ld_data, %{
          entities: [],
          relationships: [],
          context: %{},
          triples: [],
          confidence_scores: %{}
        })
        |> assign(:stats, stats)
        |> process_initial_jsonld_extraction()
        |> assign(:model_mode, model_mode())
        |> assign(:loading, false)

      {:error, reason} ->
        socket
        |> assign(:loading, false)
        |> put_flash(:error, "Failed to load LSP methods: #{inspect(reason)}")
    end
  end

  defp model_mode do
    repo_started? = match?(pid when is_pid(pid), Process.whereis(Lang.Repo))
    if repo_started?, do: :db, else: :specs
  end

  defp model_to_lv(%{name: name} = m) do
    %{
      name: name,
      category: m[:category] || "other",
      description: m[:description] || "",
      priority: m[:priority] || "Medium",
      status:
        case m[:derived_status] || m[:spec_status] do
          s when is_atom(s) -> s
          "implemented" -> :implemented
          "in_progress" -> :in_progress
          "not_implemented" -> :not_started
          "not_started" -> :not_started
          _ -> :not_started
        end,
      file_path: m[:impl_file] || "",
      impl_module: m[:impl_module],
      impl_function: m[:impl_function],
      impl_arity: m[:impl_arity]
    }
  end

  defp parse_lsp_markdown, do: {:ok, {[], ""}}

  defp extract_methods_from_markdown(_content), do: []

  defp parse_markdown_line(_line_index_tuple, acc), do: acc

  defp parse_table_row(_line, _category, _line_number), do: nil

  defp parse_method_line(line, category, line_number) do
    # Extract status
    status =
      cond do
        String.contains?(line, "✅") -> :implemented
        String.contains?(line, "🚧") -> :in_progress
        String.contains?(line, "❌") -> :not_started
        true -> :not_started
      end

    # Extract method name (usually in backticks or after status)
    method_name =
      case Regex.run(~r/`([^`]+)`/, line) do
        [_, name] ->
          name

        nil ->
          line
          |> String.replace(~r/[❌🚧✅]/, "")
          |> String.trim()
          |> String.split("|")
          |> List.first()
          |> String.trim()
      end

    # Extract description - handle both table format and simple format
    description =
      cond do
        # Table format: | `method` | status | priority | description | file |
        String.contains?(line, "|") ->
          parts = String.split(line, "|")

          if length(parts) >= 5 do
            Enum.at(parts, 3, "") |> String.trim()
          else
            line
            |> String.replace(~r/^[❌🚧✅]\s*/, "")
            |> String.replace("`#{method_name}`", "")
            |> String.replace(~r/^[|`\s-]+/, "")
            |> String.trim()
          end

        # Simple format: ❌ `method` - description
        true ->
          line
          |> String.replace(~r/^[❌🚧✅]\s*/, "")
          |> String.replace("`#{method_name}`", "")
          |> String.replace(~r/^[|`\s-]+/, "")
          |> String.trim()
      end

    # Extract priority from description or default
    {priority, clean_description} = extract_priority_from_description(description)

    # Extract file path if present
    file_path = extract_file_path(method_name, category)

    %{
      id: "method-#{line_number}-#{String.replace(method_name, ".", "-")}",
      name: method_name,
      status: status,
      category: category,
      description: clean_description,
      priority: priority,
      file_path: file_path,
      line_number: line_number,
      last_modified: get_file_last_modified(file_path)
    }
  end

  defp extract_priority_from_description(description) do
    cond do
      String.contains?(description, "🔴") or String.contains?(description, "Critical") ->
        {"Critical", String.replace(description, ~r/[🔴]|Critical/, "") |> String.trim()}

      String.contains?(description, "🟡") or String.contains?(description, "High") ->
        {"High", String.replace(description, ~r/[🟡]|High/, "") |> String.trim()}

      String.contains?(description, "🟢") or String.contains?(description, "Medium") ->
        {"Medium", String.replace(description, ~r/[🟢]|Medium/, "") |> String.trim()}

      true ->
        {"Medium", description}
    end
  end

  defp extract_file_path(_method_name, _category), do: ""

  defp parse_status("❌"), do: :not_started
  defp parse_status("🚧"), do: :in_progress
  defp parse_status("✅"), do: :implemented
  defp parse_status(_), do: :not_started

  defp extract_category_from_method(_method), do: "other"

  defp extract_categories(methods) do
    methods
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp calculate_stats(methods) do
    total = length(methods)

    counts =
      methods
      |> Enum.group_by(& &1.status)
      |> Map.new(fn {status, list} -> {status, length(list)} end)

    %{
      total: total,
      implemented: Map.get(counts, :implemented, 0),
      in_progress: Map.get(counts, :in_progress, 0),
      not_started: Map.get(counts, :not_started, 0),
      completion_rate:
        if(total > 0,
          do: Float.round(Map.get(counts, :implemented, 0) / total * 100, 1),
          else: 0.0
        )
    }
  end

  defp apply_filters(socket) do
    methods = socket.assigns.lsp_methods
    category = socket.assigns.selected_category
    priority = socket.assigns.selected_priority
    query = socket.assigns.search_query

    filtered_methods =
      methods
      |> filter_by_category(category)
      |> filter_by_priority(priority)
      |> filter_by_search(query)

    assign(socket, :filtered_methods, filtered_methods)
  end

  defp filter_by_category(methods, "all"), do: methods

  defp filter_by_category(methods, category) do
    Enum.filter(methods, &(&1.category == category))
  end

  defp filter_by_priority(methods, "all"), do: methods

  defp filter_by_priority(methods, priority) do
    Enum.filter(methods, &(String.downcase(&1.priority) == String.downcase(priority)))
  end

  defp filter_by_search(methods, ""), do: methods

  defp filter_by_search(methods, query) do
    query_lower = String.downcase(query)

    Enum.filter(methods, fn method ->
      String.contains?(String.downcase(method.name), query_lower) ||
        String.contains?(String.downcase(method.description), query_lower) ||
        String.contains?(String.downcase(method.category), query_lower)
    end)
  end

  defp update_method_status(method_name, new_status) do
    attrs = %{name: method_name, spec_status: to_spec_status(new_status)}
    SpecStore.upsert_method(attrs)
  end

  defp update_method_description(method_name, new_description) do
    attrs = %{name: method_name, description: new_description}
    SpecStore.upsert_method(attrs)
  end

  defp update_method_priority(method_name, new_priority) do
    attrs = %{name: method_name, priority: new_priority}
    SpecStore.upsert_method(attrs)
  end

  defp update_status_in_content(content, method_name, new_status) do
    status_emoji =
      case new_status do
        "not_started" -> "❌"
        "in_progress" -> "🚧"
        "implemented" -> "✅"
        _ -> "❌"
      end

    # Replace the status for the specific method
    pattern = ~r/^(\|\s*`#{Regex.escape(method_name)}`\s*\|\s*)([❌✅🚧])(\s*\|.*?)$/m

    Regex.replace(pattern, content, fn _, prefix, _old_status, suffix ->
      prefix <> status_emoji <> suffix
    end)
  end

  defp update_description_in_content(content, method_name, new_description) do
    # Replace the description for the specific method
    pattern =
      ~r/^(\|\s*`#{Regex.escape(method_name)}`\s*\|\s*[❌✅🚧]\s*\|\s*\w+\s*\|\s*)([^|]+)(\s*\|.*?)$/m

    Regex.replace(pattern, content, fn _, prefix, _old_description, suffix ->
      prefix <> new_description <> suffix
    end)
  end

  defp update_priority_in_content(content, method_name, new_priority) do
    # Replace the priority for the specific method
    pattern = ~r/^(\|\s*`#{Regex.escape(method_name)}`\s*\|\s*[❌✅🚧]\s*\|\s*)(\w+)(\s*\|.*?)$/m

    Regex.replace(pattern, content, fn _, prefix, _old_priority, suffix ->
      prefix <> new_priority <> suffix
    end)
  end

  defp bulk_update_method_status(from_status, to_status) do
    with {:ok, methods} <- SpecStore.read_all_methods() do
      target =
        Enum.filter(methods, fn m ->
          (m[:spec_status] || m[:derived_status]) in [from_status, to_string(from_status)]
        end)

      Enum.reduce(target, 0, fn m, acc ->
        case SpecStore.upsert_method(%{name: m[:name], spec_status: to_spec_status(to_status)}) do
          {:ok, _} -> acc + 1
          _ -> acc
        end
      end)
    else
      _ -> 0
    end
  end

  defp add_new_method(method_data) do
    # Expect keys: "method", "priority", "description", "category", "file_path"
    attrs = %{
      name: method_data["method"],
      category: method_data["category"],
      priority: method_data["priority"],
      description: method_data["description"],
      spec_status: "not_implemented",
      impl_file: method_data["file_path"]
    }

    SpecStore.upsert_method(attrs)
  end

  defp delete_method(method_name) do
    SpecStore.delete_method(method_name)
  end

  defp to_spec_status(status) when is_binary(status), do: status
  defp to_spec_status(:implemented), do: "implemented"
  defp to_spec_status(:in_progress), do: "in_progress"
  defp to_spec_status(:not_started), do: "not_implemented"

  defp build_method_table_row(_method_data), do: ""

  defp append_method_to_section(content, _method_line, _category), do: content

  defp read_implementation_file(file_path) do
    case FSScanner.preview(file_path, max_lines: 1000) do
      {:ok, content} when is_list(content) -> {:ok, Enum.join(content, "\n")}
      {:ok, content} when is_binary(content) -> {:ok, content}
      {:error, :file_not_found} -> {:error, :file_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_stub_file(file_path) do
    # Ensure directory exists
    dir_path = Path.dirname(file_path)

    try do
      File.mkdir_p!(dir_path)
    rescue
      _ -> :ok
    end

    # Generate stub content based on file type
    stub_content = generate_stub_content(file_path)

    case write_file(file_path, stub_content) do
      :ok -> {:ok, stub_content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_stub_content(file_path) do
    module_name = path_to_module_name(file_path)

    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      LSP Implementation for #{module_name}

      This module implements the Language Server Protocol methods for AI-first text intelligence.
      Generated by the LANG LSP Master Tracker - first of its kind.
      \"\"\"

      use GenServer
      require Logger

      # TODO: Implement LSP methods for this module

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      def init(_opts) do
        {:ok, %{}}
      end

      # Placeholder implementation - replace with actual LSP method handlers
      def handle_method(method, params, context) do
        Logger.info("Handling LSP method: \#{method} with params: \#{inspect(params)}")

        case method do
          _ ->
            {:error, :method_not_found}
        end
      end

      def placeholder do
        {:error, :not_implemented}
      end
    end
    """
  end

  defp path_to_module_name(file_path) do
    file_path
    |> String.replace_prefix("lib/", "")
    |> String.replace_suffix(".ex", "")
    |> String.split("/")
    |> Enum.map(&Macro.camelize/1)
    |> Enum.join(".")
  end

  defp write_file(file_path, content) do
    case File.write(file_path, content) do
      :ok ->
        Phoenix.PubSub.broadcast(
          Lang.PubSub,
          "lsp_editor:file_changes",
          {:file_changed, file_path}
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp save_markdown_changes(content) do
    write_file(@lsp_doc_path, content)
  end

  defp export_to_csv(methods) do
    headers = [
      "Method,Status,Priority,Description,File Path,Category,Implementation Exists,Last Modified"
    ]

    rows =
      Enum.map(methods, fn method ->
        [
          method.method,
          status_to_string(method.status),
          method.priority,
          method.description,
          method.file_path,
          method.category,
          method.implementation_exists,
          method.last_modified || "Unknown"
        ]
        |> Enum.join(",")
      end)

    [headers | rows] |> Enum.join("\n")
  end

  defp status_to_string(:not_started), do: "Not Started"
  defp status_to_string(:in_progress), do: "In Progress"
  defp status_to_string(:implemented), do: "Implemented"

  defp file_exists?(file_path), do: File.exists?(file_path)

  defp get_file_last_modified(file_path) do
    case File.stat(file_path) do
      {:ok, %{mtime: mtime}} ->
        mtime
        |> NaiveDateTime.from_erl!()
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_string()

      {:error, _} ->
        nil
    end
  end

  defp extract_markdown_ld(content) do
    case LinkedDataExtractor.extract(content, :markdown_ld,
           extract_context: true,
           extract_entities: true,
           extract_relationships: true
         ) do
      {:ok, linked_data} ->
        linked_data

      {:error, reason} ->
        Logger.warning("Failed to extract Markdown-LD: #{inspect(reason)}")
        %{entities: [], relationships: [], context: %{}, triples: [], confidence_scores: %{}}
    end
  end

  defp enhance_methods_with_semantic_data(methods, markdown_ld_data) do
    Enum.map(methods, fn method ->
      related_entities = find_related_entities(method, markdown_ld_data.entities)
      semantic_confidence = calculate_semantic_confidence(method, markdown_ld_data)

      method
      |> Map.put(:related_entities, related_entities)
      |> Map.put(:semantic_confidence, semantic_confidence)
      |> Map.put(:jsonld_context, extract_method_context(method, markdown_ld_data.context))
    end)
  end

  defp find_related_entities(method, entities) do
    method_name = method.name |> to_string() |> String.downcase()

    entities
    |> Enum.filter(fn entity ->
      entity_type = JSONLD.get(entity, "type", "") |> to_string() |> String.downcase()
      entity_name = JSONLD.get(entity, "name", "") |> to_string() |> String.downcase()

      # Match by method name or LSP-specific types
      String.contains?(entity_name, method_name) or
        entity_type in ["lsp_method", "language_server_method", "completion_item", "diagnostic"]
    end)
    # Limit for performance
    |> Enum.take(10)
  end

  defp calculate_semantic_confidence(method, markdown_ld_data) do
    base_confidence = if method.status == :implemented, do: 0.9, else: 0.5

    # Boost confidence based on semantic richness
    related_count = length(find_related_entities(method, markdown_ld_data.entities))
    context_boost = if map_size(markdown_ld_data.context) > 0, do: 0.1, else: 0.0
    entity_boost = min(related_count * 0.05, 0.2)

    min(base_confidence + context_boost + entity_boost, 1.0)
  end

  # New helper functions for JSON-LD integration

  defp process_markdown_ld_async(socket, content) do
    socket = assign(socket, :jsonld_processing, true)

    # Process JSON-LD in a background task
    parent = self()

    Task.start(fn ->
      try do
        linked_data = extract_markdown_ld(content)
        send(parent, {:markdown_ld_processed, linked_data})
      rescue
        error ->
          send(parent, {:markdown_ld_error, error})
      end
    end)

    socket
  end

  defp enhance_entities_with_jsonld(entities, markdown_ld_data) do
    context = markdown_ld_data.context

    Enum.map(entities, fn entity ->
      # Expand entity properties using JSON-LD context
      expanded_props = expand_entity_properties(entity, context)

      entity
      |> Map.put("expanded_properties", expanded_props)
      |> Map.put("jsonld_type", infer_jsonld_type(entity))
      |> Map.put("confidence_boost", calculate_confidence_boost(entity, markdown_ld_data))
    end)
  end

  defp expand_entity_properties(entity, context) when is_map(entity) and is_map(context) do
    entity
    |> Enum.map(fn {key, value} ->
      expanded_key = JSONLD.get(context, key, key)
      {expanded_key, value}
    end)
    |> Enum.into(%{})
  end

  defp expand_entity_properties(entity, _context), do: entity

  defp infer_jsonld_type(entity) do
    entity_type = Map.get(entity, "type", "")

    case String.downcase(entity_type) do
      "lsp_method" -> "https://lang.ai/schema/LSPMethod"
      "completion_item" -> "https://lang.ai/schema/CompletionItem"
      "diagnostic" -> "https://lang.ai/schema/Diagnostic"
      "hover_info" -> "https://lang.ai/schema/HoverInformation"
      _ -> "https://schema.org/Thing"
    end
  end

  defp calculate_confidence_boost(entity, markdown_ld_data) do
    base_boost = 0.0

    # Boost for entities with URIs
    uri_boost = if Map.has_key?(entity, "uri"), do: 0.1, else: 0.0

    # Boost for entities with relationships
    relationship_count =
      markdown_ld_data.relationships
      |> Enum.count(fn rel ->
        rel.subject == Map.get(entity, "id") or rel.object == Map.get(entity, "id")
      end)

    relationship_boost = min(relationship_count * 0.05, 0.15)

    base_boost + uri_boost + relationship_boost
  end

  defp update_method_semantic_confidence(socket, enhanced_entities) do
    updated_methods =
      socket.assigns.lsp_methods
      |> Enum.map(fn method ->
        method_entities =
          Enum.filter(enhanced_entities, fn entity ->
            method_name = to_string(method.name) |> String.downcase()
            entity_name = Map.get(entity, "name", "") |> String.downcase()
            String.contains?(entity_name, method_name)
          end)

        if length(method_entities) > 0 do
          avg_confidence =
            method_entities
            |> Enum.map(&Map.get(&1, "confidence_boost", 0.0))
            |> Enum.sum()
            |> Kernel./(length(method_entities))

          Map.put(method, :enhanced_semantic_confidence, avg_confidence)
        else
          method
        end
      end)

    assign(socket, :lsp_methods, updated_methods)
  end

  defp enhance_methods_with_linked_data(socket, linked_data) do
    enhanced_methods = enhance_methods_with_semantic_data(socket.assigns.lsp_methods, linked_data)

    socket
    |> assign(:lsp_methods, enhanced_methods)
    |> assign(:semantic_summary, build_semantic_summary(linked_data))
  end

  defp build_semantic_summary(linked_data) do
    %{
      "total_entities" => length(linked_data.entities),
      "total_relationships" => length(linked_data.relationships),
      "total_triples" => length(linked_data.triples),
      "lsp_methods" => count_entities_by_type(linked_data.entities, "lsp_method"),
      "completion_items" => count_entities_by_type(linked_data.entities, "completion_item"),
      "diagnostics" => count_entities_by_type(linked_data.entities, "diagnostic"),
      "confidence" => calculate_overall_confidence(linked_data),
      "context_vocabularies" => extract_vocabularies(linked_data.context)
    }
  end

  defp count_entities_by_type(entities, type) do
    entities
    |> Enum.count(fn entity ->
      entity_type = JSONLD.get(entity, "type", "") |> String.downcase()
      entity_type == type
    end)
  end

  defp calculate_overall_confidence(linked_data) do
    if length(linked_data.entities) == 0 do
      0.0
    else
      total_confidence =
        linked_data.entities
        |> Enum.map(&Map.get(&1, :confidence, 0.5))
        |> Enum.sum()

      (total_confidence / length(linked_data.entities))
      |> Float.round(2)
    end
  end

  defp extract_vocabularies(context) when is_map(context) do
    context
    |> Map.values()
    |> Enum.filter(&is_binary/1)
    |> Enum.filter(&String.contains?(&1, ["://", "schema.org", "lang.ai"]))
    |> Enum.uniq()
  end

  defp extract_vocabularies(_), do: []

  defp extract_method_context(method, context) do
    method_name = to_string(method.name)

    context
    |> Enum.filter(fn {_key, value} ->
      is_binary(value) and String.contains?(value, method_name)
    end)
    |> Enum.into(%{})
  end

  defp process_initial_jsonld_extraction(socket) do
    # Extract JSON-LD from any existing content
    if socket.assigns.raw_markdown != "" do
      process_markdown_ld_async(socket, socket.assigns.raw_markdown)
    else
      socket
    end
  end

  defp build_path(socket, extra_params \\ %{}) do
    query_params = []

    query_params =
      if socket.assigns.selected_category != "all" do
        [{"category", socket.assigns.selected_category} | query_params]
      else
        query_params
      end

    query_params =
      if socket.assigns.selected_priority != "all" do
        [{"priority", socket.assigns.selected_priority} | query_params]
      else
        query_params
      end

    query_params =
      if socket.assigns.search_query != "" do
        [{"search", socket.assigns.search_query} | query_params]
      else
        query_params
      end

    query_params =
      if socket.assigns.edit_mode != :view do
        [{"mode", Atom.to_string(socket.assigns.edit_mode)} | query_params]
      else
        query_params
      end

    # Add any extra params
    query_params = Map.to_list(extra_params) ++ query_params

    query_string =
      case query_params do
        [] -> ""
        params -> "?" <> URI.encode_query(params)
      end

    "/admin/lsp-editor" <> query_string
  end
end
