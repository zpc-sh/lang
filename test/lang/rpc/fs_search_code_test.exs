defmodule Lang.RPC.FsSearchCodeTest do
  use ExUnit.Case, async: true

  alias Lang.RPC.Router

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "fs_search_code_" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    File.mkdir_p!(root)
    File.write!(Path.join(root, "sample.js"), "function greet() { return 'hi' }\n")
    on_exit(fn -> File.rm_rf(root) end)
    {:ok, root: root}
  end

  test "lang.fs.search_code finds function in js", %{root: root} do
    patt = "(function_declaration name: (identifier) @function)"

    {:ok, %{matches: matches}} =
      Router.dispatch(%{}, "lang.fs.search_code", %{
        "root_path" => root,
        "language" => "javascript",
        "pattern" => patt,
        "max_results" => 10
      })

    assert is_list(matches)
  end
end
