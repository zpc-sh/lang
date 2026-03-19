defmodule Lang.RPC.FsScanTest do
  use ExUnit.Case, async: true

  alias Lang.RPC.Router

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "fs_scan_" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    File.mkdir_p!(Path.join(root, "sub"))
    File.write!(Path.join(root, "a.txt"), "hello\n")
    File.write!(Path.join(root, "sub/b.txt"), "world\n")
    on_exit(fn -> File.rm_rf(root) end)
    {:ok, root: root}
  end

  test "lang.fs.scan returns tree and stats", %{root: root} do
    {:ok, %{path: ^root, tree: tree, stats: stats}} =
      Router.dispatch(%{}, "lang.fs.scan", %{"path" => root, "max_depth" => 5})

    assert is_map(tree)
    assert stats.total_files >= 2
    assert stats.total_directories >= 1
  end

  defp collect_paths(%{"path" => path, "children" => nil}), do: [path]

  defp collect_paths(%{"path" => path, "children" => children}) when is_list(children) do
    [path | Enum.flat_map(children, &collect_paths/1)]
  end

  defp collect_paths(%{path: path, children: nil}), do: [path]

  defp collect_paths(%{path: path, children: children}) when is_list(children) do
    [path | Enum.flat_map(children, &collect_paths/1)]
  end

  test "lang.fs.scan respects include/exclude globs", %{root: root} do
    # Create additional files
    File.mkdir_p!(Path.join(root, "ignored"))
    File.write!(Path.join(root, "keep.exs"), "IO.puts(:ok)\n")
    File.write!(Path.join(root, "ignored/drop.txt"), "drop\n")

    params = %{
      "path" => root,
      "max_depth" => 5,
      "include_globs" => ["**/*.exs"],
      "exclude_globs" => ["**/ignored/**"],
      "stats" => true
    }

    {:ok, %{tree: tree}} = Router.dispatch(%{}, "lang.fs.scan", params)
    paths = collect_paths(tree)

    assert Enum.any?(paths, &String.ends_with?(&1, "/keep.exs"))
    refute Enum.any?(paths, &String.contains?(&1, "/ignored/"))
  end
end
