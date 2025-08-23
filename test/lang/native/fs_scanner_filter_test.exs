defmodule Lang.Native.FSScannerFilterTest do
  use ExUnit.Case, async: false

  alias Lang.Native.FSScanner

  @tmp_root Path.join([File.cwd!(), "tmp", "fs_scanner_test"]) 

  setup do
    dir = Path.join(@tmp_root, Integer.to_string(:erlang.unique_integer([:monotonic, :positive])))
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    # Tree:
    # lib/file1.ex
    # test/file2.exs
    # ignore_me/skip.txt
    # node_modules/dep.js
    # big/big.bin (> 2KB)
    # README.md
    File.mkdir_p!(Path.join(dir, "lib"))
    File.mkdir_p!(Path.join(dir, "test"))
    File.mkdir_p!(Path.join(dir, "ignore_me"))
    File.mkdir_p!(Path.join(dir, "node_modules"))
    File.mkdir_p!(Path.join(dir, "big"))

    File.write!(Path.join(dir, "lib/file1.ex"), "defmodule A do\nend\n")
    File.write!(Path.join(dir, "test/file2.exs"), "defmodule ATest do\nend\n")
    File.write!(Path.join(dir, "ignore_me/skip.txt"), "SKIP\n")
    File.write!(Path.join(dir, "node_modules/dep.js"), "module.exports = {}\n")
    File.write!(Path.join(dir, "README.md"), "# Hello\n")

    big_path = Path.join(dir, "big/big.bin")
    big_data = :binary.copy(<<0>>, 4096)
    File.write!(big_path, big_data)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, root: dir}
  end

  defp collect_paths(%{path: path, children: nil}), do: [path]

  defp collect_paths(%{path: path, children: children}) when is_list(children) do
    [path | Enum.flat_map(children, &collect_paths/1)]
  end

  test "include/exclude globs and max file size are enforced", %{root: root} do
    {:ok, %{tree: tree, stats: stats}} =
      FSScanner.scan(root,
        max_depth: 10,
        include_globs: ["**/*.exs"],
        exclude_globs: ["**/ignore_me/**", "**/node_modules/**"],
        max_file_size_bytes: 1024,
        stats: true
      )

    paths = collect_paths(tree)

    # Only .exs file should be included among files
    assert Enum.any?(paths, &String.ends_with?(&1, "/test/file2.exs"))
    refute Enum.any?(paths, &String.ends_with?(&1, "/lib/file1.ex"))
    refute Enum.any?(paths, &String.contains?(&1, "/ignore_me/"))
    refute Enum.any?(paths, &String.contains?(&1, "/node_modules/"))
    refute Enum.any?(paths, &String.ends_with?(&1, "/big/big.bin"))

    # Stats should count only included files
    assert is_integer(stats.total_files)
    assert stats.total_files >= 1
  end
end

