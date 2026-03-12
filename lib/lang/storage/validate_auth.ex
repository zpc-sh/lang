defmodule Lang.Storage.ValidateAuth do
  @moduledoc "Bearer token auth implemented"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.storage.validate_auth"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    if dirup_enabled?() do
      Lang.Storage.Folder.validate_auth()
    else
      {:error, :folder_disabled}
    end
  end

  defp dirup_enabled? do
    val = System.get_env("FOLDER_ENABLED") || System.get_env("LANG_FOLDER_ENABLED") || "0"
    String.downcase(val) in ["1", "true", "yes", "on"]
  end
end
