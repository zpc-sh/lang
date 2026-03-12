# defmodule Lang.Polyglot.Transpilers do
#   @moduledoc """
#   Transpilers that convert polyglot markdown into target formats.
#   """

#   defmodule Behaviour do
#     @callback transpile(Kyozo.Polyglot.t()) :: {:ok, any()} | {:error, term()}
#   end

#   defmodule Docker do
#     @behaviour Behaviour

#     def transpile(%{artifacts: artifacts}) do
#       dockerfiles = Enum.filter(artifacts, &(&1.type == :dockerfile))

#       case dockerfiles do
#         [%{content: content} | _] ->
#           {:ok,
#            %{
#              dockerfile: content,
#              buildable: true,
#              command: "docker build -t image:latest ."
#            }}

#         [] ->
#           {:error, :no_dockerfile_found}
#       end
#     end
#   end

#   defmodule Terraform do
#     @behaviour Behaviour

#     def transpile(%{artifacts: artifacts, metadata: metadata}) do
#       tf_blocks = Enum.filter(artifacts, &(&1.type == :terraform))

#       {:ok,
#        %{
#          configuration: merge_terraform_blocks(tf_blocks),
#          variables: metadata["terraform_vars"] || %{},
#          plan_command: "terraform plan",
#          apply_command: "terraform apply -auto-approve"
#        }}
#     end

#     defp merge_terraform_blocks(blocks) do
#       blocks
#       |> Enum.map(& &1.content)
#       |> Enum.join("\n\n")
#     end
#   end

#   defmodule Kubernetes do
#     @behaviour Behaviour

#     def transpile(%{artifacts: artifacts}) do
#       manifests = Enum.filter(artifacts, &(&1.type == :kubernetes))

#       {:ok,
#        %{
#          manifests: Enum.map(manifests, & &1.content),
#          apply_command: "kubectl apply -f -",
#          namespace: detect_namespace(manifests)
#        }}
#     end

#     defp detect_namespace(manifests) do
#       # Extract namespace from manifests
#       "default"
#     end
#   end

#   defmodule Git do
#     @behaviour Behaviour

#     def transpile(%{artifacts: artifacts, metadata: metadata}) do
#       files = Enum.filter(artifacts, &(&1.type == :file))

#       {:ok,
#        %{
#          files: Enum.map(files, &{&1.path, &1.content}),
#          init_commands: [
#            "git init",
#            "git add .",
#            ~s(git commit -m "#{metadata["commit_message"] || "Initial commit from polyglot markdown"}")
#          ]
#        }}
#     end
#   end

#   defmodule Bash do
#     @behaviour Behaviour

#     def transpile(%{artifacts: artifacts}) do
#       scripts = Enum.filter(artifacts, &(&1.type == :bash || &1.type == :executable))

#       {:ok,
#        %{
#          script: merge_scripts(scripts),
#          shebang: "#!/bin/bash",
#          executable: true
#        }}
#     end

#     defp merge_scripts(scripts) do
#       scripts
#       |> Enum.map(& &1.content)
#       |> Enum.join("\n\n")
#     end
#   end

#   defmodule Identity do
#     @behaviour Behaviour

#     def transpile(polyglot) do
#       {:ok, polyglot}
#     end
#   end
# end
