defmodule LangWeb.LspChannelIntegrationTest do
  use ExUnit.Case, async: false
  use Phoenix.ChannelTest

  @endpoint LangWeb.Endpoint

  test "connects with test_bypass and handles rpc.initialize and fs.preview" do
    # Connect to the LSP socket with test bypass
    assert {:ok, socket} = connect(LangWeb.LspSocket, %{"test_bypass" => "true"})

    # Join a session topic
    {:ok, _reply, socket} = subscribe_and_join(socket, LangWeb.LspChannel, "lsp:session-1", %{})

    # Initialize
    ref =
      push(socket, "json", %{
        "jsonrpc" => "2.0",
        "id" => "1",
        "method" => "rpc.initialize",
        "params" => %{"client" => %{"name" => "itest"}}
      })

    assert_reply(ref, :ok, reply)
    assert reply["@context"]

    # FS preview
    path = Path.join(System.tmp_dir!(), "lsp_int_preview.txt")
    File.write!(path, "line\n")

    ref2 =
      push(socket, "json", %{
        "jsonrpc" => "2.0",
        "id" => "2",
        "method" => "lang.fs.preview",
        "params" => %{"path" => path, "max_lines" => 1}
      })

    assert_reply(ref2, :ok, reply2)
    assert get_in(reply2, ["result", "path"]) == path
  end

  test "fs.search over channel returns results" do
    # Connect with bypass
    assert {:ok, socket} = connect(LangWeb.LspSocket, %{"test_bypass" => "true"})
    {:ok, _reply, socket} = subscribe_and_join(socket, LangWeb.LspChannel, "lsp:session-2", %{})

    # Prepare a temp dir
    root =
      Path.join(
        System.tmp_dir!(),
        "chan_fs_search_" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    File.mkdir_p!(root)
    File.write!(Path.join(root, "x.txt"), "TODO: channel test\n")

    ref =
      push(socket, "json", %{
        "jsonrpc" => "2.0",
        "id" => "3",
        "method" => "lang.fs.search",
        "params" => %{"root_path" => root, "pattern" => "TODO"}
      })

    assert_reply(ref, :ok, reply)
    assert get_in(reply, ["result", "root_path"]) == root
    results = get_in(reply, ["result", "results"]) || []
    assert is_list(results)
  end

  test "fs.search_code over channel returns matches list" do
    # Connect with bypass
    assert {:ok, socket} = connect(LangWeb.LspSocket, %{"test_bypass" => "true"})
    {:ok, _reply, socket} = subscribe_and_join(socket, LangWeb.LspChannel, "lsp:session-3", %{})

    # Prepare a temp dir with a JS function
    root =
      Path.join(
        System.tmp_dir!(),
        "chan_fs_search_code_" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    File.mkdir_p!(root)
    File.write!(Path.join(root, "sample.js"), "function greet() { return 'hi' }\n")
    patt = "(function_declaration name: (identifier) @function)"

    ref =
      push(socket, "json", %{
        "jsonrpc" => "2.0",
        "id" => "4",
        "method" => "lang.fs.search_code",
        "params" => %{
          "root_path" => root,
          "language" => "javascript",
          "pattern" => patt,
          "max_results" => 5
        }
      })

    assert_reply(ref, :ok, reply)
    matches = get_in(reply, ["result", "matches"]) || []
    assert is_list(matches)
  end

  test "fs.scan over channel returns tree and stats" do
    # Connect with bypass
    assert {:ok, socket} = connect(LangWeb.LspSocket, %{"test_bypass" => "true"})
    {:ok, _reply, socket} = subscribe_and_join(socket, LangWeb.LspChannel, "lsp:session-4", %{})

    # Prepare a temp tree
    root =
      Path.join(
        System.tmp_dir!(),
        "chan_fs_scan_" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    File.mkdir_p!(Path.join(root, "sub"))
    File.write!(Path.join(root, "a.txt"), "hello\n")
    File.write!(Path.join(root, "sub/b.txt"), "world\n")

    params = %{
      "path" => root,
      "max_depth" => 5,
      "include_hidden" => false,
      "include_globs" => ["**/*.txt"],
      "exclude_globs" => ["**/ignored/**"],
      "max_file_size_bytes" => 0
    }

    ref =
      push(socket, "json", %{
        "jsonrpc" => "2.0",
        "id" => "5",
        "method" => "lang.fs.scan",
        "params" => params
      })

    assert_reply(ref, :ok, reply)
    assert get_in(reply, ["result", "path"]) == root
    assert is_map(get_in(reply, ["result", "tree"]))
    stats = get_in(reply, ["result", "stats"]) || %{}
    assert is_map(stats)
  end

  test "fs.scan globs and excludes over channel are enforced" do
    # Connect with bypass
    assert {:ok, socket} = connect(LangWeb.LspSocket, %{"test_bypass" => "true"})
    {:ok, _reply, socket} = subscribe_and_join(socket, LangWeb.LspChannel, "lsp:session-5", %{})

    # Prepare a temp tree
    root =
      Path.join(
        System.tmp_dir!(),
        "chan_fs_scan_globs_" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    File.mkdir_p!(Path.join(root, "ignored"))
    File.write!(Path.join(root, "match.exs"), "IO.puts(:ok)\n")
    File.write!(Path.join(root, "ignored/nope.txt"), "nope\n")

    params = %{
      "path" => root,
      "include_globs" => ["**/*.exs"],
      "exclude_globs" => ["**/ignored/**"],
      "stats" => true
    }

    ref =
      push(socket, "json", %{
        "jsonrpc" => "2.0",
        "id" => "6",
        "method" => "lang.fs.scan",
        "params" => params
      })

    assert_reply(ref, :ok, reply)
    tree = get_in(reply, ["result", "tree"]) || %{}
    # Flatten a simple list of paths
    paths = flatten_paths(tree)
    assert Enum.any?(paths, &String.ends_with?(&1, "/match.exs"))
    refute Enum.any?(paths, &String.contains?(&1, "/ignored/"))
  end

  defp flatten_paths(%{"path" => path, "children" => nil}), do: [path]

  defp flatten_paths(%{"path" => path, "children" => children}) when is_list(children) do
    [path | Enum.flat_map(children, &flatten_paths/1)]
  end
end
