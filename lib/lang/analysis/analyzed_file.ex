defmodule Lang.Analysis.AnalyzedFile do
  use Ecto.Schema
  import Ecto.Changeset

  alias Lang.Analysis.{AnalysisSession, Violation}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending processing completed failed skipped)
  @supported_languages ~w(javascript typescript python rust elixir java go php ruby cpp c csharp)

  schema "analyzed_files" do
    field :file_path, :string
    field :file_name, :string
    field :file_extension, :string
    field :file_size_bytes, :integer
    field :content_type, :string
    field :language_detected, :string
    field :content_hash, :string
    field :content, :string
    field :status, :string, default: "pending"
    field :analysis_result, :map, default: %{}
    field :processed_at, :utc_datetime
    field :processing_time_ms, :integer

    belongs_to :analysis_session, AnalysisSession
    has_many :violations, Violation, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for creating an analyzed file.
  """
  def create_changeset(file, attrs) do
    file
    |> cast(attrs, [
      :file_path,
      :file_name,
      :file_extension,
      :file_size_bytes,
      :content_type,
      :content,
      :analysis_session_id
    ])
    |> validate_required([:file_path, :file_name, :analysis_session_id])
    |> validate_length(:file_path, max: 1000)
    |> validate_length(:file_name, max: 255)
    |> validate_number(:file_size_bytes, greater_than_or_equal_to: 0)
    |> generate_content_hash()
    |> detect_language()
    |> extract_file_extension()
  end

  @doc """
  Creates a changeset for updating analysis status.
  """
  def update_status_changeset(file, status, attrs \\ %{}) do
    file
    |> cast(attrs, [:error_message])
    |> put_change(:status, status)
    |> validate_inclusion(:status, @statuses)
    |> maybe_set_processed_at(status)
    |> validate_status_transition(file.status)
  end

  @doc """
  Creates a changeset for completing file analysis.
  """
  def complete_changeset(file, analysis_result, processing_time_ms) do
    file
    |> cast(%{analysis_result: analysis_result}, [:analysis_result])
    |> put_change(:status, "completed")
    |> put_change(:processed_at, DateTime.utc_now())
    |> put_change(:processing_time_ms, processing_time_ms)
    |> validate_analysis_result()
  end

  @doc """
  Creates a changeset for failing file analysis.
  """
  def fail_changeset(file, error_message) do
    file
    |> cast(%{}, [])
    |> put_change(:status, "failed")
    |> put_change(:processed_at, DateTime.utc_now())
    |> put_change(:analysis_result, %{error: error_message})
    |> validate_required([:analysis_result])
  end

  @doc """
  Creates a changeset for skipping file analysis.
  """
  def skip_changeset(file, reason) do
    file
    |> cast(%{}, [])
    |> put_change(:status, "skipped")
    |> put_change(:processed_at, DateTime.utc_now())
    |> put_change(:analysis_result, %{skipped_reason: reason})
  end

  # Private functions

  defp generate_content_hash(changeset) do
    case get_field(changeset, :content) do
      nil ->
        changeset

      content when is_binary(content) ->
        hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
        put_change(changeset, :content_hash, hash)

      _ ->
        changeset
    end
  end

  defp detect_language(changeset) do
    file_extension = get_field(changeset, :file_extension)
    file_name = get_field(changeset, :file_name)

    language =
      detect_language_by_extension(file_extension) || detect_language_by_filename(file_name)

    if language do
      put_change(changeset, :language_detected, language)
    else
      changeset
    end
  end

  defp extract_file_extension(changeset) do
    case get_field(changeset, :file_name) do
      nil ->
        changeset

      file_name ->
        extension = Path.extname(file_name)
        put_change(changeset, :file_extension, extension)
    end
  end

  defp detect_language_by_extension(extension) when is_binary(extension) do
    case String.downcase(extension) do
      ".js" -> "javascript"
      ".mjs" -> "javascript"
      ".jsx" -> "javascript"
      ".ts" -> "typescript"
      ".tsx" -> "typescript"
      ".py" -> "python"
      ".pyx" -> "python"
      ".pyw" -> "python"
      ".rs" -> "rust"
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".java" -> "java"
      ".kt" -> "kotlin"
      ".go" -> "go"
      ".php" -> "php"
      ".rb" -> "ruby"
      ".cpp" -> "cpp"
      ".cc" -> "cpp"
      ".cxx" -> "cpp"
      ".c" -> "c"
      ".h" -> "c"
      ".cs" -> "csharp"
      ".fs" -> "fsharp"
      ".vb" -> "vb"
      ".swift" -> "swift"
      ".m" -> "objective-c"
      ".scala" -> "scala"
      ".clj" -> "clojure"
      ".hs" -> "haskell"
      ".elm" -> "elm"
      ".dart" -> "dart"
      ".lua" -> "lua"
      ".r" -> "r"
      ".sql" -> "sql"
      ".sh" -> "shell"
      ".bash" -> "shell"
      ".zsh" -> "shell"
      ".fish" -> "shell"
      ".ps1" -> "powershell"
      ".html" -> "html"
      ".htm" -> "html"
      ".css" -> "css"
      ".scss" -> "scss"
      ".sass" -> "sass"
      ".less" -> "less"
      ".json" -> "json"
      ".xml" -> "xml"
      ".yaml" -> "yaml"
      ".yml" -> "yaml"
      ".toml" -> "toml"
      ".ini" -> "ini"
      ".conf" -> "config"
      ".config" -> "config"
      ".md" -> "markdown"
      ".markdown" -> "markdown"
      ".rst" -> "restructuredtext"
      ".tex" -> "latex"
      ".dockerfile" -> "dockerfile"
      _ -> nil
    end
  end

  defp detect_language_by_extension(_), do: nil

  defp detect_language_by_filename(filename) when is_binary(filename) do
    case String.downcase(filename) do
      "dockerfile" -> "dockerfile"
      "makefile" -> "makefile"
      "rakefile" -> "ruby"
      "gemfile" -> "ruby"
      "podfile" -> "ruby"
      "package.json" -> "json"
      "composer.json" -> "json"
      "cargo.toml" -> "toml"
      "pyproject.toml" -> "toml"
      ".gitignore" -> "gitignore"
      ".gitattributes" -> "gitattributes"
      ".editorconfig" -> "editorconfig"
      ".eslintrc" -> "json"
      ".prettierrc" -> "json"
      _ -> nil
    end
  end

  defp detect_language_by_filename(_), do: nil

  defp maybe_set_processed_at(changeset, status)
       when status in ["completed", "failed", "skipped"] do
    case get_field(changeset, :processed_at) do
      nil -> put_change(changeset, :processed_at, DateTime.utc_now())
      _ -> changeset
    end
  end

  defp maybe_set_processed_at(changeset, _status), do: changeset

  defp validate_status_transition(changeset, current_status) do
    new_status = get_change(changeset, :status)

    case {current_status, new_status} do
      # Valid transitions
      {"pending", "processing"} ->
        changeset

      {"pending", "skipped"} ->
        changeset

      {"pending", "failed"} ->
        changeset

      {"processing", "completed"} ->
        changeset

      {"processing", "failed"} ->
        changeset

      {"processing", "skipped"} ->
        changeset

      # No change
      {status, status} ->
        changeset

      # Invalid transitions
      {from, to} ->
        add_error(changeset, :status, "cannot transition from '#{from}' to '#{to}'")
    end
  end

  defp validate_analysis_result(changeset) do
    case get_field(changeset, :analysis_result) do
      nil ->
        add_error(changeset, :analysis_result, "is required")

      result when is_map(result) ->
        validate_analysis_result_structure(changeset, result)

      _ ->
        add_error(changeset, :analysis_result, "must be a valid JSON object")
    end
  end

  defp validate_analysis_result_structure(changeset, result) do
    # Define expected keys in analysis result
    expected_keys = [
      "parsing_info",
      "syntax_analysis",
      "semantic_analysis",
      "metrics",
      "suggestions",
      "performance_stats"
    ]

    # Validate that result has reasonable structure
    case Map.keys(result) do
      [] ->
        add_error(changeset, :analysis_result, "cannot be empty")

      keys ->
        if Enum.any?(keys, &(&1 in expected_keys)) do
          changeset
        else
          add_error(changeset, :analysis_result, "missing expected analysis data")
        end
    end
  end

  @doc """
  Returns all valid statuses.
  """
  def statuses, do: @statuses

  @doc """
  Returns all supported languages.
  """
  def supported_languages, do: @supported_languages

  @doc """
  Checks if the file is processed.
  """
  def processed?(%__MODULE__{status: status}) when status in ["completed", "failed", "skipped"],
    do: true

  def processed?(_), do: false

  @doc """
  Checks if the file analysis completed successfully.
  """
  def completed?(%__MODULE__{status: "completed"}), do: true
  def completed?(_), do: false

  @doc """
  Checks if the file analysis failed.
  """
  def failed?(%__MODULE__{status: "failed"}), do: true
  def failed?(_), do: false

  @doc """
  Checks if the file was skipped.
  """
  def skipped?(%__MODULE__{status: "skipped"}), do: true
  def skipped?(_), do: false

  @doc """
  Returns the file size in a human-readable format.
  """
  def human_file_size(%__MODULE__{file_size_bytes: nil}), do: "Unknown"
  def human_file_size(%__MODULE__{file_size_bytes: bytes}) when bytes < 1024, do: "#{bytes} B"

  def human_file_size(%__MODULE__{file_size_bytes: bytes}) when bytes < 1_048_576 do
    kb = round(bytes / 1024 * 10) / 10
    "#{kb} KB"
  end

  def human_file_size(%__MODULE__{file_size_bytes: bytes}) when bytes < 1_073_741_824 do
    mb = round(bytes / 1_048_576 * 100) / 100
    "#{mb} MB"
  end

  def human_file_size(%__MODULE__{file_size_bytes: bytes}) do
    gb = round(bytes / 1_073_741_824 * 100) / 100
    "#{gb} GB"
  end

  @doc """
  Returns a summary of the analysis result.
  """
  def analysis_summary(%__MODULE__{analysis_result: nil}), do: %{}

  def analysis_summary(%__MODULE__{analysis_result: result}) when is_map(result) do
    %{
      parsing_success: get_in(result, ["parsing_info", "success"]),
      lines_of_code: get_in(result, ["metrics", "lines_of_code"]),
      cyclomatic_complexity: get_in(result, ["metrics", "cyclomatic_complexity"]),
      suggestion_count: length(Map.get(result, "suggestions", [])),
      processing_time_ms: get_in(result, ["performance_stats", "processing_time_ms"])
    }
  end

  @doc """
  Checks if the file should be analyzed based on its properties.
  """
  # > 10MB
  def should_analyze?(%__MODULE__{file_size_bytes: bytes}) when bytes > 10_485_760, do: false

  def should_analyze?(%__MODULE__{file_extension: ext})
      when ext in [".bin", ".exe", ".dll", ".so", ".dylib"],
      do: false

  def should_analyze?(%__MODULE__{content_type: type}) when is_binary(type) do
    String.starts_with?(type, "text/") or String.starts_with?(type, "application/json")
  end

  def should_analyze?(%__MODULE__{}), do: true
end
