defmodule LangWeb.Admin.LspEditor.LspEditorLive do
  use LangWeb, :live_view

  alias Lang.Native.FSScanner
  alias Lang.TextIntelligence.MarkdownLDParser
  alias Lang.Analysis.AnalyzedFile

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

    {:ok, load_lsp_data(socket), temporary_assigns: [lsp_methods: []]}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:selected_category, params["category"] || "all")
      |> assign(:selected_priority, params["priority"] || "all")
      |> assign(:search_query, params["search"] || "")
      |> assign(:edit_mode, String.to_atom(params["mode"] || "view"))
      |> apply_filters()

    {:noreply, socket}
  end

  def handle_event("toggle_edit_mode", %{"mode" => mode}, socket) do
    new_mode = String.to_atom(mode)

    socket =
      socket
      |> assign(:edit_mode, new_mode)
      |> push_patch(to: build_path(socket, %{"mode" => mode}))

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
          |> assign(:editor_open, true)
          |> assign(:editing_file, file_path)
          |> assign(:file_content, content)

        {:noreply, socket}

      {:error, :file_not_found} ->
        # Create stub file
        case create_stub_file(file_path) do
          {:ok, content} ->
            socket =
              socket
              |> assign(:editor_open, true)
              |> assign(:editing_file, file_path)
              |> assign(:file_content, content)
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
    case save_markdown_changes(socket.assigns.raw_markdown) do
      :ok ->
        socket =
          socket
          |> assign(:unsaved_changes, false)
          |> assign(:last_saved, DateTime.utc_now())
          |> put_flash(:info, "All changes saved successfully")
          |> load_lsp_data()

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to save changes: #{inspect(reason)}")
        {:noreply, socket}
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
      {:ok, {methods, categories, raw_content}} ->
        stats = calculate_stats(methods)

        socket
        |> assign(:loading, false)
        |> assign(:lsp_methods, methods)
        |> assign(:categories, categories)
        |> assign(:raw_markdown, raw_content)
        |> assign(:stats, stats)
        |> apply_filters()

      {:error, reason} ->
        socket
        |> assign(:loading, false)
        |> put_flash(:error, "Failed to load LSP data: #{inspect(reason)}")
    end
  end

  defp parse_lsp_markdown do
    case FSScanner.preview(@lsp_doc_path, max_lines: 10000) do
      {:ok, content} ->
        methods = extract_methods_from_markdown(content)
        categories = extract_categories(methods)
        {:ok, {methods, categories, content}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_methods_from_markdown(content) do
    content
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.reduce([], &parse_markdown_line/2)
    |> Enum.reverse()
  end

  defp parse_markdown_line({line, index}, acc) do
    # Enhanced parsing for table rows that contain LSP methods
    case Regex.run(
           ~r/^\|\s*`([^`]+)`\s*\|\s*([❌✅🔄])\s*\|\s*(\w+)\s*\|\s*([^|]+)\s*\|\s*`([^`]+)`\s*\|/,
           line
         ) do
      [_, method, status, priority, description, file_path] ->
        method_data = %{
          id: "method-#{index}",
          method: String.trim(method),
          status: parse_status(String.trim(status)),
          priority: String.trim(priority),
          description: String.trim(description),
          file_path: String.trim(file_path),
          line_number: index + 1,
          category: extract_category_from_method(method),
          implementation_exists: file_exists?(String.trim(file_path)),
          last_modified: get_file_last_modified(String.trim(file_path))
        }

        [method_data | acc]

      _ ->
        # Try alternative parsing for methods without backticks around file path
        case Regex.run(
               ~r/^\|\s*`([^`]+)`\s*\|\s*([❌✅🔄])\s*\|\s*(\w+)\s*\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|/,
               line
             ) do
          [_, method, status, priority, description, file_path] ->
            method_data = %{
              id: "method-#{index}",
              method: String.trim(method),
              status: parse_status(String.trim(status)),
              priority: String.trim(priority),
              description: String.trim(description),
              file_path: String.trim(file_path),
              line_number: index + 1,
              category: extract_category_from_method(method),
              implementation_exists: file_exists?(String.trim(file_path)),
              last_modified: get_file_last_modified(String.trim(file_path))
            }

            [method_data | acc]

          _ ->
            acc
        end
    end
  end

  defp parse_status("❌"), do: :not_started
  defp parse_status("🔄"), do: :in_progress
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

    stream(socket, :filtered_methods, filtered_methods, reset: true)
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
      String.contains?(String.downcase(method.method), query_lower) ||
        String.contains?(String.downcase(method.description), query_lower) ||
        String.contains?(String.downcase(method.file_path), query_lower)
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
        "in_progress" -> "🔄"
        "implemented" -> "✅"
        _ -> "❌"
      end

    # Replace the status for the specific method
    pattern = ~r/^(\|\s*`#{Regex.escape(method_name)}`\s*\|\s*)([❌✅🔄])(\s*\|.*?)$/m

    Regex.replace(pattern, content, fn _, prefix, _old_status, suffix ->
      prefix <> status_emoji <> suffix
    end)
  end

  defp update_description_in_content(content, method_name, new_description) do
    # Replace the description for the specific method
    pattern =
      ~r/^(\|\s*`#{Regex.escape(method_name)}`\s*\|\s*[❌✅🔄]\s*\|\s*\w+\s*\|\s*)([^|]+)(\s*\|.*?)$/m

    Regex.replace(pattern, content, fn _, prefix, _old_description, suffix ->
      prefix <> new_description <> suffix
    end)
  end

  defp update_priority_in_content(content, method_name, new_priority) do
    # Replace the priority for the specific method
    pattern = ~r/^(\|\s*`#{Regex.escape(method_name)}`\s*\|\s*[❌✅🔄]\s*\|\s*)(\w+)(\s*\|.*?)$/m

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
            "in_progress" -> "🔄"
            "implemented" -> "✅"
          end

        to_emoji =
          case to_status do
            "not_started" -> "❌"
            "in_progress" -> "🔄"
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

  defp append_method_to_section(content, method_line, category) do
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
