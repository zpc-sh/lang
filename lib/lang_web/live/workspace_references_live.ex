defmodule LangWeb.WorkspaceReferencesLive do
  use LangWeb, :live_view
  import Phoenix.Component
  import Phoenix.HTML

  alias Ash.Query
  alias Lang.Workspace.{Reference, Symbol}

  @impl true
  def mount(%{"workspace_id" => workspace_id} = params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :load, 0)

    {:ok,
     socket
     |> assign(:workspace_id, workspace_id)
     |> assign(:symbol_id, params["symbol_id"])
     |> assign(:file_path, params["file_path"])
     |> stream(:references, [])}
  end

  @impl true
  def handle_info(:load, %{assigns: %{workspace_id: ws, symbol_id: sym_id}} = socket) do
    refs = list_refs(ws, sym_id)
    {:noreply, stream(socket, :references, refs, reset: true)}
  end

  defp list_refs(ws, nil) do
    case Reference |> Query.filter(workspace_id: ws) |> Query.limit(200) |> Ash.read() do
      {:ok, refs} -> refs
      _ -> []
    end
  end

  defp list_refs(_ws, sym_id) when is_binary(sym_id) do
    case Reference |> Reference.find_to(symbol_id: sym_id) do
      {:ok, refs} -> refs
      _ -> []
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
end
