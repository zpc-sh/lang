defmodule Lang.Analyses.File do
  @moduledoc """
  AnalyzedFile Resource for Analysis Domain

  Represents a single file processed during an analysis session.
  Contains the file metadata, content, analysis results, and processing status.
  """

  use Ash.Resource,
    domain: Lang.Analyses,
    data_layer: AshPostgres.DataLayer

  alias Lang.Analyses.{Run, Violation}

  postgres do
    table("analyzed_files")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :file_path, :string do
      allow_nil?(false)
      constraints(max_length: 1000)
    end

    attribute :file_name, :string do
      allow_nil?(false)
      constraints(max_length: 255)
    end

    attribute :file_extension, :string do
      allow_nil?(true)
    end

    attribute :file_size_bytes, :integer do
      allow_nil?(true)
      constraints(min: 0)
    end

    attribute :content_type, :string do
      allow_nil?(true)
    end

    attribute :language_detected, :atom do
      allow_nil?(true)

      constraints(
        one_of: [
          :javascript,
          :typescript,
          :python,
          :rust,
          :elixir,
          :java,
          :go,
          :php,
          :ruby,
          :cpp,
          :c,
          :csharp,
          :swift,
          :kotlin,
          :scala,
          :clojure,
          :haskell,
          :elm,
          :dart,
          :lua,
          :r,
          :sql,
          :shell,
          :powershell,
          :html,
          :css,
          :scss,
          :sass,
          :less,
          :json,
          :xml,
          :yaml,
          :toml,
          :ini,
          :config,
          :markdown,
          :restructuredtext,
          :latex,
          :dockerfile,
          :makefile,
          :gitignore
        ]
      )
    end

    attribute :content_hash, :string do
      allow_nil?(true)
    end

    attribute :vfs_uri, :string do
      allow_nil?(true)
      description("Content-addressed URI in Kyozo VFS (non-persisted content)")
    end

    attribute :content, :string do
      allow_nil?(true)
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:pending)
      constraints(one_of: [:pending, :processing, :completed, :failed, :skipped])
    end

    attribute :analysis_result, :map do
      allow_nil?(false)
      default(%{})
    end

    attribute :processed_at, :utc_datetime do
      allow_nil?(true)
    end

    attribute :processing_time_ms, :integer do
      allow_nil?(true)
      constraints(min: 0)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)

    attribute :workspace_id, :uuid do
      allow_nil?(true)
    end
  end

  relationships do
    belongs_to :analysis_session, Run do
      attribute_writable?(true)
    end

    # Workspace is Redis-backed; avoid cross data-layer relationship here.

    has_many :violations, Violation do
      destination_attribute(:analyzed_file_id)
    end
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :file_path,
        :file_name,
        :file_extension,
        :file_size_bytes,
        :content_type,
        :analysis_session_id
      ])

      # Support non-persisted content ingestion via argument
      argument(:raw_content, :string, allow_nil?: true)

      validate(present([:file_path, :file_name, :analysis_session_id]))

      change(fn changeset, _context ->
        # Prefer raw_content argument for hashing and VFS storage
        raw = Ash.Changeset.get_argument(changeset, :raw_content)

        case raw || Ash.Changeset.get_attribute(changeset, :content) do
          nil ->
            changeset

          content when is_binary(content) ->
            hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
            vfs_uri = Lang.Storage.VFS.put(content)

            changeset
            |> Ash.Changeset.change_attribute(:content_hash, hash)
            |> Ash.Changeset.change_attribute(:vfs_uri, vfs_uri)
            |> detect_and_set_language()

          _ ->
            changeset
        end
      end)

      change(fn changeset, _context ->
        # Extract file extension if not provided
        case {
          Ash.Changeset.get_attribute(changeset, :file_extension),
          Ash.Changeset.get_attribute(changeset, :file_name)
        } do
          {nil, file_name} when is_binary(file_name) ->
            extension = Path.extname(file_name)
            Ash.Changeset.change_attribute(changeset, :file_extension, extension)

          _ ->
            changeset
        end
      end)
    end

    update :update_status do
      accept([])
      argument(:status, :atom, allow_nil?: false)

      validate(present(:status))
      validate(one_of(:status, [:pending, :processing, :completed, :failed, :skipped]))

      change(fn changeset, _context ->
        status = Ash.Changeset.get_argument(changeset, :status)
        current_status = changeset.data.status

        case validate_status_transition(current_status, status) do
          :ok ->
            changeset = Ash.Changeset.change_attribute(changeset, :status, status)

            # Set processed_at for final states
            if status in [:completed, :failed, :skipped] and is_nil(changeset.data.processed_at) do
              Ash.Changeset.change_attribute(changeset, :processed_at, DateTime.utc_now())
            else
              changeset
            end

          {:error, message} ->
            Ash.Changeset.add_error(changeset, :status, message)
        end
      end)
    end

    update :complete do
      accept([:analysis_result])
      argument(:processing_time_ms, :integer, allow_nil?: false)

      change(fn changeset, context ->
        processing_time = context.arguments[:processing_time_ms]

        changeset
        |> Ash.Changeset.change_attribute(:status, :completed)
        |> Ash.Changeset.change_attribute(:processed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:processing_time_ms, processing_time)
      end)

      validate(present(:analysis_result))
    end

    update :fail do
      accept([])
      argument(:error_message, :string, allow_nil?: false)

      change(fn changeset, context ->
        error_message = context.arguments[:error_message]
        analysis_result = %{error: error_message}

        changeset
        |> Ash.Changeset.change_attribute(:status, :failed)
        |> Ash.Changeset.change_attribute(:processed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:analysis_result, analysis_result)
      end)
    end

    update :skip do
      accept([])
      argument(:reason, :string, allow_nil?: false)

      change(fn changeset, context ->
        reason = context.arguments[:reason]
        analysis_result = %{skipped_reason: reason}

        changeset
        |> Ash.Changeset.change_attribute(:status, :skipped)
        |> Ash.Changeset.change_attribute(:processed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:analysis_result, analysis_result)
      end)
    end

    destroy(:destroy)
  end

  code_interface do
    define(:read_all, action: :read)
    define(:by_id, action: :read, get_by: [:id])
    define(:create, action: :create)
    define(:update_status, action: :update_status)
    define(:complete, action: :complete)
    define(:fail, action: :fail)
    define(:skip, action: :skip)
    define(:destroy, action: :destroy)
  end

  preparations do
    prepare(build(load: [:violations]))
  end

  calculations do
    calculate(:is_processed, :boolean, expr(status in [:completed, :failed, :skipped]))
    calculate(:is_completed, :boolean, expr(status == :completed))
    calculate(:is_failed, :boolean, expr(status == :failed))
    calculate(:is_skipped, :boolean, expr(status == :skipped))

    calculate(
      :human_file_size,
      :string,
      expr(
        cond do
          is_nil(file_size_bytes) ->
            "Unknown"

          file_size_bytes < 1024 ->
            fragment("? || ' B'", file_size_bytes)

          file_size_bytes < 1_048_576 ->
            fragment("ROUND(? / 1024.0, 1) || ' KB'", file_size_bytes)

          file_size_bytes < 1_073_741_824 ->
            fragment("ROUND(? / 1048576.0, 2) || ' MB'", file_size_bytes)

          true ->
            fragment("ROUND(? / 1073741824.0, 2) || ' GB'", file_size_bytes)
        end
      )
    )
  end

  # Helper functions
  defp detect_and_set_language(changeset) do
    file_extension = Ash.Changeset.get_attribute(changeset, :file_extension)
    file_name = Ash.Changeset.get_attribute(changeset, :file_name)

    language =
      detect_language_by_extension(file_extension) || detect_language_by_filename(file_name)

    if language do
      Ash.Changeset.change_attribute(changeset, :language_detected, language)
    else
      changeset
    end
  end

  defp detect_language_by_extension(extension) when is_binary(extension) do
    case String.downcase(extension) do
      ".js" -> :javascript
      ".mjs" -> :javascript
      ".jsx" -> :javascript
      ".ts" -> :typescript
      ".tsx" -> :typescript
      ".py" -> :python
      ".pyx" -> :python
      ".pyw" -> :python
      ".rs" -> :rust
      ".ex" -> :elixir
      ".exs" -> :elixir
      ".java" -> :java
      ".kt" -> :kotlin
      ".go" -> :go
      ".php" -> :php
      ".rb" -> :ruby
      ".cpp" -> :cpp
      ".cc" -> :cpp
      ".cxx" -> :cpp
      ".c" -> :c
      ".h" -> :c
      ".cs" -> :csharp
      ".fs" -> :fsharp
      ".vb" -> :vb
      ".swift" -> :swift
      ".m" -> :objective_c
      ".scala" -> :scala
      ".clj" -> :clojure
      ".hs" -> :haskell
      ".elm" -> :elm
      ".dart" -> :dart
      ".lua" -> :lua
      ".r" -> :r
      ".sql" -> :sql
      ".sh" -> :shell
      ".bash" -> :shell
      ".zsh" -> :shell
      ".fish" -> :shell
      ".ps1" -> :powershell
      ".html" -> :html
      ".htm" -> :html
      ".css" -> :css
      ".scss" -> :scss
      ".sass" -> :sass
      ".less" -> :less
      ".json" -> :json
      ".xml" -> :xml
      ".yaml" -> :yaml
      ".yml" -> :yaml
      ".toml" -> :toml
      ".ini" -> :ini
      ".conf" -> :config
      ".config" -> :config
      ".md" -> :markdown
      ".markdown" -> :markdown
      ".rst" -> :restructuredtext
      ".tex" -> :latex
      ".dockerfile" -> :dockerfile
      _ -> nil
    end
  end

  defp detect_language_by_extension(_), do: nil

  defp detect_language_by_filename(filename) when is_binary(filename) do
    case String.downcase(filename) do
      "dockerfile" -> :dockerfile
      "makefile" -> :makefile
      "rakefile" -> :ruby
      "gemfile" -> :ruby
      "podfile" -> :ruby
      "package.json" -> :json
      "composer.json" -> :json
      "cargo.toml" -> :toml
      "pyproject.toml" -> :toml
      ".gitignore" -> :gitignore
      ".gitattributes" -> :gitattributes
      ".editorconfig" -> :editorconfig
      ".eslintrc" -> :json
      ".prettierrc" -> :json
      _ -> nil
    end
  end

  defp detect_language_by_filename(_), do: nil

  defp validate_status_transition(current_status, new_status) do
    case {current_status, new_status} do
      # Valid transitions
      {:pending, :processing} -> :ok
      {:pending, :skipped} -> :ok
      {:pending, :failed} -> :ok
      {:processing, :completed} -> :ok
      {:processing, :failed} -> :ok
      {:processing, :skipped} -> :ok
      # No change
      {status, status} -> :ok
      # Invalid transitions
      {from, to} -> {:error, "cannot transition from '#{from}' to '#{to}'"}
    end
  end

  # Instance helper functions
  def processed?(%{status: status}) when status in [:completed, :failed, :skipped],
    do: true

  def processed?(_), do: false

  def completed?(%{status: :completed}), do: true
  def completed?(_), do: false

  def failed?(%{status: :failed}), do: true
  def failed?(_), do: false

  def skipped?(%{status: :skipped}), do: true
  def skipped?(_), do: false

  def human_file_size(%{file_size_bytes: nil}), do: "Unknown"
  def human_file_size(%{file_size_bytes: bytes}) when bytes < 1024, do: "#{bytes} B"

  def human_file_size(%{file_size_bytes: bytes}) when bytes < 1_048_576 do
    kb = round(bytes / 1024 * 10) / 10
    "#{kb} KB"
  end

  def human_file_size(%{file_size_bytes: bytes}) when bytes < 1_073_741_824 do
    mb = round(bytes / 1_048_576 * 100) / 100
    "#{mb} MB"
  end

  def human_file_size(%{file_size_bytes: bytes}) do
    gb = round(bytes / 1_073_741_824 * 100) / 100
    "#{gb} GB"
  end

  def analysis_summary(%{analysis_result: nil}), do: %{}

  def analysis_summary(%{analysis_result: result}) when is_map(result) do
    %{
      parsing_success: get_in(result, ["parsing_info", "success"]),
      lines_of_code: get_in(result, ["metrics", "lines_of_code"]),
      cyclomatic_complexity: get_in(result, ["metrics", "cyclomatic_complexity"]),
      suggestion_count: length(Map.get(result, "suggestions", [])),
      processing_time_ms: get_in(result, ["performance_stats", "processing_time_ms"])
    }
  end

  def should_analyze?(%{file_size_bytes: bytes}) when bytes > 10_485_760, do: false

  def should_analyze?(%{file_extension: ext})
      when ext in [".bin", ".exe", ".dll", ".so", ".dylib"],
      do: false

  def should_analyze?(%{content_type: type}) when is_binary(type) do
    String.starts_with?(type, "text/") or String.starts_with?(type, "application/json")
  end

  def should_analyze?(_), do: true

  def statuses, do: [:pending, :processing, :completed, :failed, :skipped]

  def supported_languages do
    [
      :javascript,
      :typescript,
      :python,
      :rust,
      :elixir,
      :java,
      :go,
      :php,
      :ruby,
      :cpp,
      :c,
      :csharp,
      :swift,
      :kotlin,
      :scala,
      :clojure,
      :haskell,
      :elm,
      :dart,
      :lua,
      :r,
      :sql,
      :shell,
      :powershell,
      :html,
      :css,
      :scss,
      :sass,
      :less,
      :json,
      :xml,
      :yaml,
      :toml,
      :ini,
      :config,
      :markdown,
      :restructuredtext,
      :latex,
      :dockerfile,
      :makefile,
      :gitignore
    ]
  end
end
