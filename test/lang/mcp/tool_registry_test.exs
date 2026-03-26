defmodule Lang.MCP.ToolRegistryTest do
  use ExUnit.Case, async: true
  alias Lang.MCP.ToolRegistry

  describe "runtime_tools/0 read function" do
    setup do
      read_fn = ToolRegistry.__runtime_tools_for_test__()["filesystem"]["read"]["function"]
      %{read_fn: read_fn}
    end

    test "allows reading a file within the current working directory", %{read_fn: read_fn} do
      cwd = File.cwd!()
      test_file = Path.join(cwd, "test_file.txt")
      File.write!(test_file, "hello world")

      assert {:ok, "hello world"} = read_fn.(test_file)

      # Cleanup
      File.rm!(test_file)
    end

    test "allows reading a file with relative path within the current working directory", %{read_fn: read_fn} do
      cwd = File.cwd!()
      test_file = Path.join(cwd, "test_file_relative.txt")
      File.write!(test_file, "hello relative world")

      assert {:ok, "hello relative world"} = read_fn.("test_file_relative.txt")
      assert {:ok, "hello relative world"} = read_fn.("./test_file_relative.txt")

      # Cleanup
      File.rm!(test_file)
    end

    test "prevents reading a file outside the current working directory using absolute path", %{read_fn: read_fn} do
      # Create a temporary file in the OS temp directory
      tmp_dir = System.tmp_dir!()
      outside_file = Path.join(tmp_dir, "outside_file.txt")
      File.write!(outside_file, "secret")

      assert {:error, :eacces} = read_fn.(outside_file)

      # Cleanup
      File.rm!(outside_file)
    end

    test "prevents reading a file in a sibling directory with a matching prefix", %{read_fn: read_fn} do
      cwd = File.cwd!()
      # E.g. if cwd is /app/my_dir, sibling is /app/my_dir_secrets
      sibling_dir = cwd <> "_secrets"
      File.mkdir_p!(sibling_dir)
      secret_file = Path.join(sibling_dir, "secret.txt")
      File.write!(secret_file, "sibling secret")

      # Use a relative path to attempt to traverse out and into the sibling dir
      cwd_basename = Path.basename(cwd)
      traversal_path = Path.join(["..", cwd_basename <> "_secrets", "secret.txt"])

      assert {:error, :eacces} = read_fn.(traversal_path)

      # Cleanup
      File.rm!(secret_file)
      File.rmdir!(sibling_dir)
    end

    test "prevents reading a file outside the current working directory using relative path traversal", %{read_fn: read_fn} do
      # Create a file in a parent directory relative to cwd, or OS temp directory
      tmp_dir = System.tmp_dir!()
      outside_file = Path.join(tmp_dir, "outside_file_traversal.txt")
      File.write!(outside_file, "secret")

      # Construct a path traversing from cwd to the temp directory
      # This is tricky without knowing exact relationship between cwd and temp_dir,
      # but we can use an absolute path with traversal to test the expand logic.
      # Wait, the prompt says "relative path with `..` that goes outside the directory fails."
      # Let's test `../../../../../etc/passwd`
      assert {:error, :eacces} = read_fn.("../../../../../etc/passwd")

      # Cleanup
      File.rm!(outside_file)
    end
  end
end
