defmodule Elixir.Lang.LSP.Lang.Lang.Storage.UpdateUserContext do
  @moduledoc "Update user context in storage (Dirup-backed with fallback)"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.storage.update_user_context"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"user_id" => user_id, "context" => context}, _ctx)
      when is_binary(user_id) and is_map(context) do
    result =
      if dirup_enabled?() do
        Lang.Storage.Dirup.update_user_context(user_id, context)
      else
        :ok = Lang.InMemory.Store.put(:user_contexts, user_id, context)
        {:ok, %{updated: true, user_id: user_id}}
      end

    result
  end

  def handle(_params, _ctx), do: {:error, -32602, "Missing required parameters: user_id, context"}

  defp dirup_enabled? do
    val = System.get_env("DIRUP_ENABLED") || System.get_env("LANG_DIRUP_ENABLED") || "0"
    String.downcase(val) in ["1", "true", "yes", "on"]
  end
end

defmodule Elixir.Lang.LSP.Lang.Lang.Storage.GetUserContext do
  @moduledoc "Retrieve user context from storage"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.storage.get_user_context"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"user_id" => user_id}, _ctx) when is_binary(user_id) do
    result =
      if dirup_enabled?() do
        Lang.Storage.Dirup.get_user_context(user_id)
      else
        ctx = Lang.InMemory.Store.get(:user_contexts, user_id, %{})
        {:ok, %{user_id: user_id, context: ctx}}
      end

    result
  end

  def handle(_params, _ctx), do: {:error, -32602, "Missing required parameters: user_id"}

  defp dirup_enabled? do
    val = System.get_env("DIRUP_ENABLED") || System.get_env("LANG_DIRUP_ENABLED") || "0"
    String.downcase(val) in ["1", "true", "yes", "on"]
  end
end
