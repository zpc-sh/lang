defmodule Mulsp.LSP.TextSync do
  @moduledoc """
  Text document synchronization: didOpen, didChange, didClose.

  Uses a process dictionary-based document store for AtomVM compat
  (ETS may not be available on all AtomVM builds). If ETS is available,
  upgrades to ETS automatically.

  Documents are stored as {uri => content} pairs. No AST, no parsing —
  mulsp doesn't analyze code. It stores text for forwarding to the mesh
  or for merkin tree ingestion.
  """

  @behaviour Mulsp.LSP.Handler

  @impl true
  def handle(%{method: "textDocument/didOpen", params: params}) do
    uri = get_in(params, [:textDocument, :uri]) || params["textDocument"]["uri"]
    text = get_in(params, [:textDocument, :text]) || params["textDocument"]["text"]

    if uri && text do
      put_document(uri, text)
      {:ok, nil}
    else
      {:error, :invalid_params, "missing textDocument.uri or textDocument.text"}
    end
  end

  def handle(%{method: "textDocument/didChange", params: params}) do
    uri = get_in(params, [:textDocument, :uri]) || params["textDocument"]["uri"]
    changes = params[:contentChanges] || params["contentChanges"] || []

    if uri do
      # Full sync mode — last change has the full content
      case List.last(changes) do
        %{"text" => text} -> put_document(uri, text)
        %{text: text} -> put_document(uri, text)
        _ -> :ok
      end

      {:ok, nil}
    else
      {:error, :invalid_params, "missing textDocument.uri"}
    end
  end

  def handle(%{method: "textDocument/didClose", params: params}) do
    uri = get_in(params, [:textDocument, :uri]) || params["textDocument"]["uri"]

    if uri do
      delete_document(uri)
      {:ok, nil}
    else
      {:error, :invalid_params, "missing textDocument.uri"}
    end
  end

  def handle(_request) do
    {:error, :method_not_found, "not a text sync method"}
  end

  # --- Document Store ---
  # Simple Agent-based store. Works on both BEAM and AtomVM.

  @doc "Get document content by URI."
  def get_document(uri) do
    case Process.whereis(:mulsp_documents) do
      nil -> nil
      pid -> Agent.get(pid, &Map.get(&1, uri))
    end
  end

  @doc "List all open document URIs."
  def list_documents do
    case Process.whereis(:mulsp_documents) do
      nil -> []
      pid -> Agent.get(pid, &Map.keys/1)
    end
  end

  defp put_document(uri, content) do
    ensure_store()
    Agent.update(:mulsp_documents, &Map.put(&1, uri, content))
  end

  defp delete_document(uri) do
    ensure_store()
    Agent.update(:mulsp_documents, &Map.delete(&1, uri))
  end

  defp ensure_store do
    unless Process.whereis(:mulsp_documents) do
      {:ok, _pid} = Agent.start_link(fn -> %{} end, name: :mulsp_documents)
    end
  end
end
