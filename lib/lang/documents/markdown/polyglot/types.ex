defmodule Kyozo.Markdown.Types do
  @moduledoc """
  Internal markdown type classification to guide downstream transforms.
  Not a user-facing spec.
  """

  @doc """
  Detect the singular purpose of a markdown file from its metadata.
  """
  def detect_type(content) do
    case extract_type_declaration(content) do
      {:ok, %{"@type" => "kyozo:Dockerfile"}} ->
        {:dockerfile, %{executor: "docker", action: "build"}}

      {:ok, %{"@type" => "kyozo:Configuration"}} ->
        {:config, %{parser: "yaml", mountable: true}}

      {:ok, %{"@type" => "kyozo:Repository"}} ->
        {:git_repo, %{vcs: "git", bare: false}}

      {:ok, %{"@type" => "kyozo:Executable"}} ->
        {:executable, %{interpreter: detect_interpreter(content)}}

      {:ok, %{"@type" => "kyozo:Database"}} ->
        {:database, %{engine: "sqlite", embedded: true}}

      {:ok, %{"@type" => "kyozo:Service"}} ->
        {:service, %{runtime: "systemd", autostart: true}}

      _ ->
        # Default - just a doc
        {:documentation, %{}}
    end
  end

  defp extract_type_declaration(content) do
    case Regex.run(~r/<!-- ({[^}]*"@type"[^}]*}) -->/, content) do
      [_, json] -> Jason.decode(json)
      _ -> {:error, :no_type}
    end
  end

  @doc """
  Capabilities and constraints used internally.
  """
  def capabilities(type) do
    case type do
      :dockerfile ->
        %{
          can_build: true,
          can_execute: false,
          can_mount: false,
          produces: "docker_image"
        }

      :config ->
        %{
          can_build: false,
          can_execute: false,
          can_mount: true,
          produces: "mounted_config"
        }

      :git_repo ->
        %{
          can_build: false,
          # git commands
          can_execute: true,
          # as a git repo
          can_mount: true,
          produces: "git_repository"
        }

      :executable ->
        %{
          can_build: false,
          can_execute: false,
          can_mount: false,
          produces: "process"
        }

      :database ->
        %{
          # schema
          can_build: true,
          # queries
          can_execute: true,
          # as a db file
          can_mount: true,
          produces: "sqlite_db"
        }
    end
  end

  defp detect_interpreter(content) do
    cond do
      String.contains?(content, "#!/usr/bin/env python") -> "python"
      String.contains?(content, "#!/usr/bin/env ruby") -> "ruby"
      String.contains?(content, "#!/usr/bin/env node") -> "node"
      String.contains?(content, "#!/bin/bash") -> "bash"
      String.contains?(content, "#!/bin/sh") -> "sh"
      String.contains?(content, "```elixir") -> "elixir"
      String.contains?(content, "```python") -> "python"
      String.contains?(content, "```javascript") -> "javascript"
      String.contains?(content, "```bash") -> "bash"
      true -> "unknown"
    end
  end
end

# (Examples removed; internal use only)
