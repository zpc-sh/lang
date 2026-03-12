defmodule Lang.RPC.FsSearchTest do
  use ExUnit.Case, async: true

  alias Lang.RPC.Router

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "fs_search_" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    File.mkdir_p!(root)
    File.write!(Path.join(root, "notes.txt"), "TODO: fix this test\nHello world\n")
    on_exit(fn -> File.rm_rf(root) end)
    {:ok, root: root}
  end

  test "lang.fs.search returns results", %{root: root} do
    {:ok, %{root_path: ^root, results: results}} =
      Router.dispatch(%{}, "lang.fs.search", %{"root_path" => root, "pattern" => "TODO"})

    assert is_list(results)
    assert Enum.any?(results)
  end
end
