defmodule Lang.Storage.URI do
  @moduledoc """
  Parse and normalize storage URIs across backends:
  - file://absolute/path
  - vfs://team/<team_id>/workspace/<workspace_id>/path
  - oci://<owner>/<repo>[@sha256:...|:tag]
  """

  def parse(nil), do: {:file, File.cwd!(), "."}

  def parse("file://" <> abs) do
    {:file, "/", abs}
  end

  def parse("vfs://" <> rest) do
    parts = String.split(rest, "/", trim: true)
    case parts do
      ["team", team_id, "workspace", workspace_id | path_parts] ->
        {:vfs, %{team_id: team_id, workspace_id: workspace_id, path: Enum.join(path_parts, "/")}}
      _ -> {:error, :invalid_vfs_uri}
    end
  end

  def parse("oci://" <> rest) do
    # oci://owner/repo@sha256:... or oci://owner/repo:tag
    case String.split(rest, ["@", ":"], parts: 3) do
      [owner_repo, "sha256", digest] ->
        {:oci, owner_repo_path(owner_repo) |> Map.put(:reference, "sha256:" <> digest)}
      [owner_repo, tag] ->
        {:oci, owner_repo_path(owner_repo) |> Map.put(:reference, tag)}
      _ -> {:error, :invalid_oci_uri}
    end
  end

  def parse(other) do
    # Treat as relative file path under cwd
    {:file, File.cwd!(), other}
  end

  defp owner_repo_path(owner_repo) do
    [owner | repo_parts] = String.split(owner_repo, "/", trim: true)
    %{owner: owner, repo: Enum.join(repo_parts, "/")}
  end
end

