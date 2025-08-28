defmodule LangWeb.LspEditor.LspEditorLive do
  use LangWeb, :live_view

  alias Lang.Native.FSScanner
  alias Lang.TextIntelligence.MarkdownLDParser
  alias Lang.Analysis.AnalyzedFile
  alias Kyozo.Lang.UniversalParser.LinkedDataExtractor

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

    {:noreply, socket}
  end

  def handle_event(
        "update_semantic_data",
        %{"entities" => entities, "entity_count" => count},
        socket
      ) do
    socket =
      socket
      |> assign(:semantic_entities, entities)
      |> assign(:semantic_entity_count, count)
      |> put_flash(:info, "Found #{count} semantic entities")

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

  def handle_info({:file_changed, @lsp_doc_path}, socket) do
    socket =
      socket
      |> put_flash(:info, "LSP documentation updated externally")
      |> load_lsp_data()

    {:noreply, socket}
  end

  # Private functions

  defp load_lsp_data(socket) do
    case parse_lsp_markdown() do
      {:ok, {methods, raw_content}} ->
        categories = extract_categories(methods)
        stats = calculate_stats(methods)

        # Extract markdown_ld data if available
        markdown_ld_data = extract_markdown_ld(raw_content)

        socket
        |> assign(:lsp_methods, methods)
        |> assign(:categories, categories)
        |> assign(:raw_markdown, raw_content)
        |> assign(:markdown_ld_data, markdown_ld_data)
        |> assign(:stats, stats)
        |> assign(:loading, false)

      {:error, reason} ->
        socket
        |> assign(:loading, false)
        |> put_flash(:error, "Failed to load LSP data: #{reason}")
    end
  end

  defp parse_lsp_markdown do
    # Use native FSScanner for reading the markdown file
    case FSScanner.preview(@lsp_doc_path, max_lines: 20_000) do
      {:ok, lines} when is_list(lines) ->
        content = Enum.join(lines, "\n")
        methods = extract_methods_from_markdown(content)
        {:ok, {methods, content}}

      {:ok, content} when is_binary(content) ->
        methods = extract_methods_from_markdown(content)
        {:ok, {methods, content}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_methods_from_markdown(content) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce(%{methods: [], current_category: nil}, &parse_markdown_line/2)
    |> Map.get(:methods)
  end

  defp parse_markdown_line({line, index}, acc) do
    cond do
      # Category headers (## or ###)
      String.match?(line, ~r/^##+ /) ->
        category =
          line
          |> String.replace(~r/^##+ /, "")
          |> String.trim()
          |> String.downcase()

        %{acc | current_category: category}

      # Table rows: | `method` | status | priority | description | file |
      String.match?(line, ~r/^\s*\|/) and String.contains?(line, "`") and
          not String.contains?(line, "| Method |") and not String.match?(line, ~r/^\s*\|\s*-+/) ->
        case parse_table_row(line, acc.current_category || "general", index) do
          nil -> acc
          method -> %{acc | methods: [method | acc.methods]}
        end

      # Method lines (containing status indicators)
      String.contains?(line, "❌") or String.contains?(line, "🚧") or String.contains?(line, "✅") ->
        method = parse_method_line(line, acc.current_category || "general", index)
        %{acc | methods: [method | acc.methods]}

      true ->
        acc
    end
  end

  defp parse_table_row(line, category, line_number) do
    parts =
      line
      |> String.trim()
      |> String.trim_leading("|")
      |> String.trim_trailing("|")
      |> String.split("|")
      |> Enum.map(&String.trim/1)

    # Expect: [method, status, priority, description, file]
    if length(parts) >= 5 do
      [method_cell, status_cell, priority_cell, desc_cell | rest] = parts
      file_cell = Enum.at(rest, 0, "")

      method_name =
        case Regex.run(~r/`([^`]+)`/, method_cell) do
          [_, name] -> name
          _ -> method_cell
        end

      status =
        cond do
          String.contains?(status_cell, "✅") -> :implemented
          String.contains?(status_cell, "🚧") -> :in_progress
          String.contains?(status_cell, "❌") -> :not_started
          true -> :not_started
        end

      priority = String.trim(priority_cell)
      description = String.trim(desc_cell)

      file_path =
        case Regex.run(~r/`([^`]+)`/, file_cell) do
          [_, fp] -> fp
          _ -> String.trim(file_cell)
        end

      %{
        id: "method-#{line_number}-#{String.replace(method_name, ".", "-")}",
        name: method_name,
        status: status,
        category: category,
        description: description,
        priority: priority,
        file_path: if(file_path == "", do: extract_file_path(method_name, category), else: file_path),
        line_number: line_number,
        last_modified: get_file_last_modified(file_path)
      }
    else
      nil
    end
  end

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

  defp extract_file_path(method_name, category) do
    # Prefer semantic category from method prefix (e.g., "lang.think.foo" -> "think")
    preferred_category = extract_category_from_method(method_name) || category || "other"

    base_name =
      method_name
      |> String.replace(~r/[\/:]/, "_")
      |> String.downcase()

    "lib/lang/lsp/#{preferred_category}/#{base_name}.ex"
  end

  defp parse_status("❌"), do: :not_started
  defp parse_status("🚧"), do: :in_progress
  defp parse_status("✅"), do: :implemented
  defp parse_status(_), do: :not_started

  defp extract_category_from_method(method) do
    case String.split(method, ".") do
      ["lang", category | _] -> category
      [category | _] -> category
      _ -> "other"
    end
  end

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
    case FSScanner.preview(@lsp_doc_path, max_lines: 10000) do
      {:ok, content} ->
        updated_content = update_status_in_content(content, method_name, new_status)
        write_file(@lsp_doc_path, updated_content)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_method_description(method_name, new_description) do
    case FSScanner.preview(@lsp_doc_path, max_lines: 10000) do
      {:ok, content} ->
        updated_content = update_description_in_content(content, method_name, new_description)
        write_file(@lsp_doc_path, updated_content)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_method_priority(method_name, new_priority) do
    case FSScanner.preview(@lsp_doc_path, max_lines: 10000) do
      {:ok, content} ->
        updated_content = update_priority_in_content(content, method_name, new_priority)
        write_file(@lsp_doc_path, updated_content)

      {:error, reason} ->
        {:error, reason}
    end
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
    case FSScanner.preview(@lsp_doc_path, max_lines: 10000) do
      {:ok, content} ->
        from_emoji =
          case from_status do
            "not_started" -> "❌"
            "in_progress" -> "🚧"
            "implemented" -> "✅"
          end

        to_emoji =
          case to_status do
            "not_started" -> "❌"
            "in_progress" -> "🚧"
            "implemented" -> "✅"
          end

        updated_content = String.replace(content, from_emoji, to_emoji)

        case write_file(@lsp_doc_path, updated_content) do
          :ok ->
            # Count how many were changed
            original_count = String.split(content, from_emoji) |> length() |> Kernel.-(1)
            new_count = String.split(updated_content, from_emoji) |> length() |> Kernel.-(1)
            original_count - new_count

          {:error, _} ->
            0
        end

      {:error, _} ->
        0
    end
  end

  defp add_new_method(method_data) do
    case FSScanner.preview(@lsp_doc_path, max_lines: 10000) do
      {:ok, content} ->
        method_line = build_method_table_row(method_data)
        # Find appropriate section to add the method
        updated_content = append_method_to_section(content, method_line, method_data["category"])
        write_file(@lsp_doc_path, updated_content)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_method(method_name) do
    case FSScanner.preview(@lsp_doc_path, max_lines: 10000) do
      {:ok, content} ->
        pattern = ~r/^\|\s*`#{Regex.escape(method_name)}`\s*\|.*?\|\s*$/m
        updated_content = Regex.replace(pattern, content, "")
        write_file(@lsp_doc_path, updated_content)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_method_table_row(method_data) do
    status_emoji =
      case method_data["status"] do
        "not_started" -> "❌"
        "in_progress" -> "🔄"
        "implemented" -> "✅"
        _ -> "❌"
      end

    "| `#{method_data["method"]}` | #{status_emoji} | #{method_data["priority"]} | #{method_data["description"]} | `#{method_data["file_path"]}` |"
  end

  defp append_method_to_section(content, method_line, _category) do
    # Simple approach: append to end of appropriate category section
    # In a more sophisticated version, we'd parse the markdown structure
    content <> "\n" <> method_line
  end

  defp read_implementation_file(file_path) do
    case FSScanner.preview(file_path, max_lines: 1000) do
      {:ok, content} -> {:ok, content}
      {:error, :file_not_found} -> {:error, :file_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_stub_file(file_path) do
    # Ensure directory exists
    dir_path = Path.dirname(file_path)
    File.mkdir_p!(dir_path)

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

  defp file_exists?(file_path) do
    File.exists?(file_path)
  end

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
    case LinkedDataExtractor.extract_from_content(content, :markdown_ld) do
      {:ok, linked_data} ->
        %{
          entities: linked_data.entities || [],
          relationships: linked_data.relationships || [],
          context: linked_data.context || %{},
          triples: linked_data.triples || [],
          confidence_scores: linked_data.confidence_scores || %{}
        }

      {:error, _reason} ->
        %{entities: [], relationships: [], context: %{}, triples: [], confidence_scores: %{}}
    end
  end

  defp enhance_methods_with_semantic_data(methods, markdown_ld_data) do
    Enum.map(methods, fn method ->
      # Find related entities for this method
      related_entities = find_related_entities(method, markdown_ld_data.entities)

      # Calculate semantic confidence
      semantic_confidence = calculate_semantic_confidence(method, markdown_ld_data)

      method
      |> Map.put(:related_entities, related_entities)
      |> Map.put(:semantic_confidence, semantic_confidence)
      |> Map.put(:has_semantic_data, length(related_entities) > 0)
    end)
  end

  defp find_related_entities(method, entities) do
    method_text = "#{method.name} #{method.description}" |> String.downcase()

    Enum.filter(entities, fn entity ->
      entity_text = "#{entity.text || ""} #{entity.type || ""}" |> String.downcase()
      String.contains?(method_text, entity_text) or String.contains?(entity_text, method_text)
    end)
  end

  defp calculate_semantic_confidence(method, markdown_ld_data) do
    base_confidence = if method.status == :implemented, do: 0.9, else: 0.5

    # Boost confidence if method has related entities
    entity_boost =
      if length(find_related_entities(method, markdown_ld_data.entities)) > 0, do: 0.1, else: 0.0

    # Boost confidence if method has relationships
    relationship_boost =
      markdown_ld_data.relationships
      |> Enum.any?(fn rel -> String.contains?("#{rel}", method.name) end)
      |> if(do: 0.1, else: 0.0)

    min(1.0, base_confidence + entity_boost + relationship_boost)
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
