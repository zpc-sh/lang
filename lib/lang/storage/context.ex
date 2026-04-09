defmodule Elixir.Lang.LSP.Lang.Lang.Storage.UpdateUserContext do
  @moduledoc "Update user context in storage (Folder-backed with fallback)"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.storage.update_user_context"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"user_id" => user_id, "context" => context}, ctx)
      when is_binary(user_id) and is_map(context) do
    Lang.Storage.DataHandle.execute(
      "user_context",
      "update_user_context",
      fn entry ->
        case entry.backend do
          :folder ->
            Lang.Storage.Folder.update_user_context(user_id, context)

          _ ->
            :ok = Lang.InMemory.Store.put(:user_contexts, user_id, context)
            {:ok, %{updated: true, user_id: user_id}}
        end
      end,
      ctx
    )
  end

  def handle(_params, _ctx), do: {:error, -32602, "Missing required parameters: user_id, context"}

end

defmodule Elixir.Lang.LSP.Lang.Lang.Storage.GetUserContext do
  @moduledoc "Retrieve user context from storage"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.storage.get_user_context"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"user_id" => user_id}, ctx) when is_binary(user_id) do
    Lang.Storage.DataHandle.execute(
      "user_context",
      "get_user_context",
      fn entry ->
        case entry.backend do
          :folder ->
            Lang.Storage.Folder.get_user_context(user_id)

          _ ->
            user_ctx = Lang.InMemory.Store.get(:user_contexts, user_id, %{})
            {:ok, %{user_id: user_id, context: user_ctx}}
        end
      end,
      ctx
    )
  end

  def handle(_params, _ctx), do: {:error, -32602, "Missing required parameters: user_id"}

end
