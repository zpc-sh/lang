defmodule Mix.Tasks.Lsp.Doctor do
  use Mix.Task
  @shortdoc "Diagnose first-time LSP connectivity and run basic checks"

  @moduledoc """
  Runs a quick diagnostic against the LANG LSP server:

  - TCP connect to `LSP_HOST:LSP_PORT` (defaults 127.0.0.1:4001)
  - LSP initialize handshake (via Lang.LSP.Client)
  - `rpc.ping` sanity check
  - Optional quick FS scan (depth 0)

  Usage:
    mix lsp.doctor [--host 127.0.0.1] [--port 4001] [--no-fs]

  If the server is not running, start the time-limited harness locally:
    LSP_PORT=4001 LSP_DURATION_SECONDS=900 ./scripts/lsp_harness.sh
  """

  alias Lang.LSP.Client
  alias Lang.LSP.API

  @impl true
  def run(argv) do
    Mix.Task.run("loadpaths")
    {opts, _rest, _} = OptionParser.parse(argv, strict: [host: :string, port: :integer, no_fs: :boolean])

    host = (opts[:host] || System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
    port = opts[:port] || env_int("LSP_PORT", 4001)
    no_fs? = Keyword.get(opts, :no_fs, false)

    Mix.shell().info("LSP Doctor: host=#{List.to_string(host)} port=#{port}")

    case :gen_tcp.connect(host, port, [:binary, active: false], 1_000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        Mix.shell().info("TCP connect: OK")
      {:error, reason} ->
        Mix.shell().error("TCP connect FAILED: #{inspect(reason)}")
        print_help()
        Mix.raise("Cannot connect to LSP at #{List.to_string(host)}:#{port}")
    end

    case Client.connect(host: host, port: port, timeout: 2_000, root_path: File.cwd!()) do
      {:ok, conn} ->
        Mix.shell().info("LSP initialize: OK")
        Client.disconnect(conn)
      {:error, reason} ->
        Mix.shell().error("LSP initialize FAILED: #{inspect(reason)}")
        print_help()
        Mix.raise("LSP initialization failed")
    end

    case API.ping(host: host, port: port, timeout: 1_000) do
      {:ok, _} -> Mix.shell().info("rpc.ping: OK")
      {:error, reason} ->
        Mix.shell().error("rpc.ping FAILED: #{inspect(reason)}")
        print_help()
        Mix.raise("Ping failed")
    end

    unless no_fs? do
      case API.fs_scan(File.cwd!(), %{"max_depth" => 0}, host: host, port: port, timeout: 2_000) do
        {:ok, _} -> Mix.shell().info("lang.fs.scan (depth 0): OK")
        {:error, reason} -> Mix.shell().error("lang.fs.scan FAILED: #{inspect(reason)}")
      end
    end

    # Optional Folder checks when environment is primed
    maybe_test_folder(host, port)

    Mix.shell().info("LSP Doctor: all checks passed")
  end

  defp env_int(var, default) do
    case System.get_env(var) do
      nil -> default
      val ->
        case Integer.parse(val) do
          {i, ""} -> i
          _ -> default
        end
    end
  end

  defp print_help do
    Mix.shell().info("\nHints:")
    Mix.shell().info("- Start time-limited server: LSP_PORT=4001 LSP_DURATION_SECONDS=900 ./scripts/lsp_harness.sh")
    Mix.shell().info("- Override host/port via env: LSP_HOST, LSP_PORT or flags: --host/--port")
    Mix.shell().info("- If running in a container/VM, ensure port forwarding and firewall allow TCP to the port")
    Mix.shell().info("- Check logs: /tmp/lang_lsp.err (from harness) and app logs for startup errors")
  end

  defp maybe_test_folder(host, port) do
    owner = System.get_env("FOLDER_OWNER")
    repo = System.get_env("FOLDER_REPO")
    reference = System.get_env("FOLDER_REFERENCE") || "latest"
    team = System.get_env("FOLDER_TEAM_ID")
    wid = System.get_env("FOLDER_WORKSPACE_ID")
    url = System.get_env("FOLDER_URL")

    if url do
      Mix.shell().info("Folder checks: base=#{url}")

      if owner && repo do
        case API.call("folder/registry.getManifest", %{"owner" => owner, "repo" => repo, "reference" => reference}, host: host, port: port, timeout: 3_000) do
          {:ok, _} -> Mix.shell().info("folder/registry.getManifest: OK")
          {:error, reason} -> Mix.shell().error("folder/registry.getManifest FAILED: #{inspect(reason)}")
        end
      end

      if owner && repo do
        case API.call("folder/registry.getBlob", %{"owner" => owner, "repo" => repo, "digest" => System.get_env("FOLDER_DIGEST") || "sha256:INVALID"}, host: host, port: port, timeout: 3_000) do
          {:ok, _} -> Mix.shell().info("folder/registry.getBlob: OK (or partial)")
          {:error, reason} -> Mix.shell().error("folder/registry.getBlob FAILED: #{inspect(reason)}")
        end
      end

      if team && wid do
        case API.call("folder/fs.list", %{"teamId" => team, "workspaceId" => wid, "path" => "."}, host: host, port: port, timeout: 3_000) do
          {:ok, _} -> Mix.shell().info("folder/fs.list: OK")
          {:error, reason} -> Mix.shell().error("folder/fs.list FAILED: #{inspect(reason)}")
        end
      end
    end
  end
end
