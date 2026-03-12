defmodule Lang.Storage do
  @moduledoc """
  Storage facade with billing + event tracking and pluggable adapter.

  Default adapter is `Lang.Storage.LocalFS` (uses native NIFs). You can set
  `config :lang, :storage_adapter, Lang.Storage.Folder` to proxy to Folder API
  when integrating cross-service. All functions accept a context map containing
  at least `:organization_id` and optional `:user_id`, `:session_id`.
  """

  alias Lang.Billing.Service, as: Billing
  alias Lang.Events

  use Ash.Domain

  resources do
    resource(Lang.Storage.PatternEntity)
  end

  @type ctx :: %{required(:organization_id) => String.t(), optional(:user_id) => String.t(), optional(:session_id) => String.t(), optional(:root) => String.t()}

  defp adapter do
    Application.get_env(:lang, :storage_adapter, Lang.Storage.LocalFS)
  end

  defp root_from(ctx) do
    Map.get(ctx, :root) || (Application.get_env(:lang, :workspace_root) || File.cwd!())
  end

  defp bill!(ctx, event_type, extra \\ %{}) do
    org_id = Map.get(ctx, :organization_id)
    user_id = Map.get(ctx, :user_id)
    case Billing.can_make_request?(org_id) do
      {true, _bill} ->
        _ = Events.track_event(%{event_type: event_type, organization_id: org_id, user_id: user_id, metadata: extra})
        :ok
      {false, info} -> {:error, {:billing_blocked, info}}
    end
  end

  # def list(ctx, path, opts \\ [])
  def list_files(ctx, path, opts \\ []) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_list", %{path: path}),
         {:ok, res} <- adapter().list(root_from(ctx), path, opts) do
      {:ok, res}
    else
      {:error, _} = e -> e
      other -> other
    end
  end

  def stat_file(ctx, path) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_stat", %{path: path}),
         {:ok, res} <- adapter().stat(root_from(ctx), path) do
      {:ok, res}
    else
      e -> e
    end
  end

  def read_file(ctx, path, opts \\ []) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_read", %{path: path, max_lines: Keyword.get(opts, :max_lines)}),
         {:ok, res} <- adapter().read(root_from(ctx), path, opts) do
      {:ok, res}
    else
      e -> e
    end
  end

  def preview(ctx, path, max_lines \\ 200) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_preview", %{path: path, max_lines: max_lines}),
         {:ok, res} <- adapter().preview(root_from(ctx), path, max_lines) do
      {:ok, res}
    else
      e -> e
    end
  end

  def search(ctx, pattern, opts \\ []) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_search", %{pattern: pattern, max: Keyword.get(opts, :max_results)}),
         {:ok, res} <- adapter().search(root_from(ctx), pattern, opts) do
      {:ok, res}
    else
      e -> e
    end
  end

  def search_code(ctx, language, query, opts \\ []) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_search_code", %{language: language}),
         {:ok, res} <- adapter().search_code(root_from(ctx), language, query, opts) do
      {:ok, res}
    else
      e -> e
    end
  end

  def scan_directory(ctx, opts \\ []) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_scan", %{depth: Keyword.get(opts, :max_depth)}),
         {:ok, res} <- adapter().scan(root_from(ctx), opts) do
      {:ok, res}
    else
      e -> e
    end
  end

  def write(ctx, path, content, mode \\ :replace) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_write", %{path: path, mode: mode}),
         :ok <- adapter().write(root_from(ctx), path, content, mode) do
      {:ok, %{ok: true}}
    else
      e -> e
    end
  end

  def move_file(ctx, from, to) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_move", %{from: from, to: to}),
         :ok <- adapter().move(root_from(ctx), from, to) do
      {:ok, %{ok: true}}
    else
      e -> e
    end
  end

  def delete_folders(ctx, path, recursive?) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_delete", %{path: path, recursive: recursive?}),
         :ok <- adapter().delete(root_from(ctx), path, recursive?) do
      {:ok, %{ok: true}}
    else
      e -> e
    end
  end

  # Registry conveniences (Folder adapter only)
  def registry_manifest(ctx, owner, repo, reference, opts) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_registry_manifest", %{owner: owner, repo: repo}),
         mod when is_atom(mod) <- adapter() do
      if function_exported?(mod, :registry_get_manifest, 4) do
        apply(mod, :registry_get_manifest, [owner, repo, reference, opts])
      else
        {:error, :unsupported}
      end
    else
      e -> e
    end
  end

  def registry_blob(ctx, owner, repo, digest, opts) when is_map(ctx) do
    with :ok <- bill!(ctx, "folder_registry_blob", %{owner: owner, repo: repo}),
         mod when is_atom(mod) <- adapter() do
      if function_exported?(mod, :registry_get_blob, 4) do
        apply(mod, :registry_get_blob, [owner, repo, digest, opts])
      else
        {:error, :unsupported}
      end
    else
      e -> e
    end
  end
end
