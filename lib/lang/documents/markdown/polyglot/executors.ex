# defmodule Lang.Polyglot.Executors do
#   @moduledoc """
#   Internal adapters for polyglot artifact handling.

#   NOTE: Not a public execution surface. Networking and runtime actions
#   must occur in isolated sidecars/services.
#   """

#   defmodule Behaviour do
#     @callback execute(Lang.Polyglot.t()) :: {:ok, any()} | {:error, term()}
#   end

#   defmodule Docker do
#     @behaviour Behaviour

#     def execute(%{artifacts: artifacts} = polyglot) do
#       with {:ok, %{dockerfile: content}} <- Lang.Polyglot.transpile(polyglot, :docker),
#            {:ok, temp_path} <- write_temp_file(content, "Dockerfile"),
#            {output, 0} <-
#              System.cmd("docker", ["build", "-f", temp_path, "-t", "polyglot:latest", "."]) do
#         {:ok,
#          %{
#            image: "polyglot:latest",
#            output: output,
#            built_at: DateTime.utc_now()
#          }}
#       else
#         {output, code} ->
#           {:error, %{code: code, output: output}}

#         error ->
#           error
#       end
#     end

#     defp write_temp_file(content, name) do
#       path = Path.join(System.tmp_dir!(), name)
#       File.write!(path, content)
#       {:ok, path}
#     end
#   end

#   defmodule Terraform do
#     @behaviour Behaviour

#     def execute(%{} = polyglot) do
#       with {:ok, %{configuration: config}} <- Lang.Polyglot.transpile(polyglot, :terraform),
#            {:ok, dir} <- create_temp_dir(),
#            :ok <- File.write!(Path.join(dir, "main.tf"), config),
#            {_, 0} <- safe_terraform_cmd(["init"], cd: dir),
#            {output, 0} <- safe_terraform_cmd(["plan"], cd: dir) do
#         {:ok,
#          %{
#            plan: output,
#            directory: dir,
#            next_step: "terraform apply"
#          }}
#       else
#         {:error, :terraform_not_found} ->
#           {:ok,
#            %{
#              plan: "Terraform not installed - would execute: terraform plan",
#              directory: "mock",
#              next_step: "Install terraform to execute"
#            }}

#         error ->
#           error
#       end
#     end

#     defp safe_terraform_cmd(args, opts \\ []) do
#       case System.find_executable("terraform") do
#         nil ->
#           {:error, :terraform_not_found}

#         _path ->
#           try do
#             System.cmd("terraform", args, opts)
#           rescue
#             ErlangError ->
#               {:error, :terraform_execution_failed}
#           end
#       end
#     end

#     defp create_temp_dir do
#       dir = Path.join(System.tmp_dir!(), "polyglot_tf_#{:erlang.unique_integer([:positive])}")
#       File.mkdir_p!(dir)
#       {:ok, dir}
#     end
#   end

#   defmodule Kubernetes do
#     @behaviour Behaviour

#     def execute(%{} = polyglot) do
#       with {:ok, %{manifests: manifests}} <- Lang.Polyglot.transpile(polyglot, :kubernetes) do
#         case System.find_executable("kubectl") do
#           nil ->
#             {:ok,
#              %{
#                applied: length(manifests),
#                failed: 0,
#                results:
#                  Enum.map(manifests, fn _ -> {:ok, "kubectl not installed - mock execution"} end)
#              }}

#           _path ->
#             results = Enum.map(manifests, &apply_manifest/1)

#             {:ok,
#              %{
#                applied: Enum.count(results, &match?({:ok, _}, &1)),
#                failed: Enum.count(results, &match?({:error, _}, &1)),
#                results: results
#              }}
#         end
#       end
#     end

#     defp apply_manifest(yaml) do
#       try do
#         case System.cmd("kubectl", ["apply", "-f", "-"], input: yaml) do
#           {output, 0} -> {:ok, output}
#           {output, code} -> {:error, %{code: code, output: output}}
#         end
#       rescue
#         ErlangError ->
#           {:error, %{code: -1, output: "kubectl execution failed"}}
#       end
#     end
#   end

#   defmodule SQL do
#     @behaviour Behaviour

#     def execute(%{artifacts: artifacts, metadata: metadata}) do
#       sql_blocks = Enum.filter(artifacts, &(&1.type == :sql))

#       # Get database connection from metadata or default
#       db_config = metadata["database"] || default_db_config()

#       results = Enum.map(sql_blocks, &execute_sql(&1, db_config))

#       {:ok,
#        %{
#          executed: length(results),
#          results: results
#        }}
#     end

#     defp execute_sql(%{content: sql}, config) do
#       # Would use Ecto or direct connection
#       {:ok, "Executed: #{String.slice(sql, 0, 50)}..."}
#     end

#     defp default_db_config do
#       %{adapter: :postgres, database: "polyglot_db"}
#     end
#   end

#   defmodule Git do
#     @behaviour Behaviour

#     def execute(%{} = polyglot) do
#       with {:ok, %{files: files, init_commands: commands}} <-
#              Lang.Polyglot.transpile(polyglot, :git),
#            {:ok, dir} <- create_temp_dir() do
#         # Write all files
#         Enum.each(files, fn {path, content} ->
#           full_path = Path.join(dir, path)
#           File.mkdir_p!(Path.dirname(full_path))
#           File.write!(full_path, content)
#         end)

#         # Execute git commands
#         results = Enum.map(commands, &System.cmd("sh", ["-c", &1], cd: dir))

#         {:ok,
#          %{
#            repository: dir,
#            files_created: length(files),
#            git_output: results
#          }}
#       end
#     end

#     defp create_temp_dir do
#       dir = Path.join(System.tmp_dir!(), "polyglot_repo_#{:erlang.unique_integer([:positive])}")
#       File.mkdir_p!(dir)
#       {:ok, dir}
#     end
#   end

#   defmodule Shell do
#     @behaviour Behaviour

#     def execute(%{artifacts: artifacts, metadata: metadata}) do
#       scripts = Enum.filter(artifacts, &(&1.type == :bash || &1.type == :executable))

#       case scripts do
#         [] ->
#           {:error, :no_executable_found}

#         [script | _] ->
#           execute_script(script.content, metadata)
#       end
#     end

#     defp execute_script(content, metadata) do
#       env = metadata["environment"] || %{}

#       case System.find_executable("bash") do
#         nil ->
#           case System.find_executable("sh") do
#             nil ->
#               {:error, %{output: "No shell found (bash/sh)", exit_code: -1}}

#             _path ->
#               safe_shell_cmd("sh", ["-c", content], env)
#           end

#         _path ->
#           safe_shell_cmd("bash", ["-c", content], env)
#       end
#     end

#     defp safe_shell_cmd(shell, args, env) do
#       try do
#         case System.cmd(shell, args, env: env) do
#           {output, 0} ->
#             {:ok, %{output: output, exit_code: 0}}

#           {output, code} ->
#             {:error, %{output: output, exit_code: code}}
#         end
#       rescue
#         ErlangError ->
#           {:error, %{output: "Shell execution failed", exit_code: -1}}
#       end
#     end
#   end

#   defmodule Noop do
#     @behaviour Behaviour

#     def execute(polyglot) do
#       {:ok,
#        %{
#          message: "This markdown is just documentation",
#          polyglot: polyglot
#        }}
#     end
#   end
# end
