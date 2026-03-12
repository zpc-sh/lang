defmodule LangWeb.WorkspaceSymbolsLive do
  use LangWeb, :live_view
  import Phoenix.Component
  import Phoenix.HTML

  alias Ash.Query
  alias Lang.Workspace.Symbol

  @impl true
  def mount(%{"workspace_id" => workspace_id}, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :load, 0)

    {:ok,
     socket
     |> assign(:workspace_id, workspace_id)
     |> assign(:filter, %{"file_path" => "", "name" => "", "type" => ""})
     |> assign(:root, "")
     |> assign(:offset, 0)
     |> assign(:symbols_empty?, true)
     |> stream(:symbols, [])}
  end

  @impl true
  def handle_info(:load, %{assigns: %{workspace_id: ws, offset: off}} = socket) do
    symbols = list_symbols(ws, nil, nil, nil, off)

    {:noreply,
     socket
     |> assign(:symbols_empty?, symbols == [])
     |> stream(:symbols, symbols, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filter" => %{"file_path" => fp, "name" => name, "type" => type}}, socket) do
    ws = socket.assigns.workspace_id
    symbols = list_symbols(ws, blank_to_nil(fp), blank_to_nil(name), blank_to_nil(type), 0)

    {:noreply,
     socket
     |> assign(:filter, %{"file_path" => fp, "name" => name, "type" => type})
     |> assign(:offset, 0)
     |> assign(:symbols_empty?, symbols == [])
     |> stream(:symbols, symbols, reset: true)}
  end

  @impl true
  def handle_event("ingest", %{"root" => root} = _params, socket) do
    ws = socket.assigns.workspace_id
    root = if root == "" do
      # Try to resolve from workspace metadata
      case fetch_workspace_root(ws) do
        {:ok, r} -> r
        _ -> nil
      end
    else
      root
    end

    cond do
      is_binary(root) and root != "" ->
        case Lang.Workspace.Service.ingest_all_symbols(ws, root, sync_small: true, max_depth: 6) do
          {:ok, %{files: n, mode: mode}} ->
            {:noreply, put_flash(socket, :info, "Ingest queued (#{n} files, #{mode})")}
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Ingest failed: #{inspect(reason)}")}
        end

      true ->
        {:noreply, put_flash(socket, :error, "Provide a workspace root path")}
    end
  end

  @impl true
  def handle_event("reingest_file", %{"file_path" => path}, socket) do
    ws = socket.assigns.workspace_id
    %{"workspace_id" => ws, "file_path" => path}
    |> Lang.Workers.SymbolIngestWorker.new(queue: :lsp)
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Re-ingest enqueued for #{path}")}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    ws = socket.assigns.workspace_id
    off = socket.assigns.offset + page_size()
    %{"file_path" => fp, "name" => name, "type" => type} = socket.assigns.filter
    symbols = list_symbols(ws, blank_to_nil(fp), blank_to_nil(name), blank_to_nil(type), off)

    {:noreply,
     socket
     |> assign(:offset, off)
     |> assign(:symbols_empty?, symbols == [])
     |> stream(:symbols, symbols, reset: true)}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    ws = socket.assigns.workspace_id
    off = max(socket.assigns.offset - page_size(), 0)
    %{"file_path" => fp, "name" => name, "type" => type} = socket.assigns.filter
    symbols = list_symbols(ws, blank_to_nil(fp), blank_to_nil(name), blank_to_nil(type), off)

    {:noreply,
     socket
     |> assign(:offset, off)
     |> assign(:symbols_empty?, symbols == [])
     |> stream(:symbols, symbols, reset: true)}
  end

  defp fetch_workspace_root(id) do
    require Ash.Query
    case Lang.Workspace.Workspace
         |> Ash.Query.filter(id == ^id)
         |> Ash.read_one() do
      {:ok, ws} ->
        case ws && ws.metadata do
          %{} = meta ->
            root = meta["root_path"] || meta[:root_path]
            if is_binary(root) and root != "", do: {:ok, root}, else: {:error, :no_root}
          _ -> {:error, :no_meta}
        end

      other -> other
    end
  end

  defp list_symbols(workspace_id, file_path, name, type, offset) do
    base =
      case file_path do
        nil -> Symbol |> Query.filter(workspace_id: workspace_id)
        _ -> Symbol |> Query.filter(workspace_id: workspace_id, file_path: file_path)
      end

    # Fetch enough for offset + page; Ash offset may not be available everywhere, so do local slice
    limit = offset + page_size()
    syms =
      case base |> Query.limit(limit) |> Ash.read() do
        {:ok, list} -> list
        _ -> []
      end

    syms
    |> maybe_filter_name(name)
    |> maybe_filter_type(type)
    |> Enum.drop(offset)
    |> Enum.take(page_size())
  end

  defp maybe_filter_name(list, nil), do: list
  defp maybe_filter_name(list, name) when is_binary(name) and name != "" do
    n = String.downcase(name)
    Enum.filter(list, fn s -> String.contains?(String.downcase(s.name || ""), n) end)
  end
  defp maybe_filter_name(list, _), do: list

  defp maybe_filter_type(list, nil), do: list
  defp maybe_filter_type(list, type) when is_binary(type) and type != "" do
    t = String.downcase(type)
    Enum.filter(list, fn s -> String.downcase(to_string(s.type || "")) == t end)
  end
  defp maybe_filter_type(list, _), do: list

  defp page_size, do: 200

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
end
