defmodule Lang.Workspace.Resolver do
  @moduledoc """
  Resolve a workspace root path from various identifiers.

  Priority:
  1) explicit workspace_root in params/config
  2) workspace_id → lookup `Lang.Workspace.Workspace.metadata.root_path`
  3) repository triple %{org,user,workspace} (TODO: implement when schema supports it)
  """

  require Ash.Query

  @spec resolve_root(%{workspace_root: binary() | nil, workspace_id: binary() | nil, repository: map() | nil}) ::
          {:ok, binary()} | {:error, term()}
  def resolve_root(%{workspace_root: root}) when is_binary(root) and root != "" do
    {:ok, root}
  end

  def resolve_root(%{workspace_id: id}) when is_binary(id) and id != "" do
    try do
      q =
        Lang.Workspace.Workspace
        |> Ash.Query.filter(id == ^id)
        |> Ash.read_one()

      case q do
        {:ok, ws} ->
          case ws && ws.metadata do
            %{} = meta ->
              root = meta["root_path"] || meta[:root_path]
              if is_binary(root) and root != "", do: {:ok, root}, else: {:error, :root_not_set}
            _ -> {:error, :no_metadata}
          end

        other -> {:error, other}
      end
    rescue
      e -> {:error, {:workspace_lookup_failed, e}}
    end
  end

  def resolve_root(%{repository: %{"org" => org, "user" => user, "workspace" => ws}}) when is_binary(ws) do
    try do
      # First narrow by workspace name, then filter by metadata org/user in memory
      import Ash.Query
      ws_mod = Lang.Workspace.Workspace

      # Prefer first-class fields if present (org/user), fallback to metadata matching.
      attrs = Ash.Resource.Info.attributes(ws_mod) |> Enum.map(& &1.name)
      query =
        cond do
          :org in attrs and :user in attrs ->
            ws_mod
            |> filter(name == ^ws)
            |> (fn q -> if is_binary(org), do: filter(q, org == ^org), else: q end).()
            |> (fn q -> if is_binary(user), do: filter(q, user == ^user), else: q end).()
            |> Ash.read()

          true ->
            ws_mod
            |> filter(name == ^ws)
            |> Ash.read()
        end

      case query do
        {:ok, list} when is_list(list) ->
          match =
            Enum.find(list, fn rec ->
              cond do
                :org in attrs and :user in attrs ->
                  (is_nil(org) or rec.org == org) and (is_nil(user) or rec.user == user)
                true ->
                  meta = rec.metadata || %{}
                  match_org = case org do nil -> true; _ -> (meta["org"] || meta[:org]) == org end
                  match_user = case user do nil -> true; _ -> (meta["user"] || meta[:user]) == user end
                  match_org and match_user
              end
            end)

          case match do
            nil -> {:error, :workspace_not_found}
            rec ->
              meta = rec.metadata || %{}
              root = meta["root_path"] || meta[:root_path]
              if is_binary(root) and root != "", do: {:ok, root}, else: {:error, :root_not_set}
          end

        other -> {:error, other}
      end
    rescue
      e -> {:error, {:repo_resolution_failed, e}}
    end
  end

  def resolve_root(_), do: {:error, :workspace_unresolved}
end
