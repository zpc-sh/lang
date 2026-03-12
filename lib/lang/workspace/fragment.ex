defmodule Lang.Workspace.Fragment do
  use Ash.Resource,
    domain: Lang.Workspaces,
    data_layer: Lang.Ash.RedisDataLayer

  attributes do
    uuid_primary_key(:id)

    attribute :file_path, :string do
      allow_nil?(false)
    end

    attribute :fragment_type, :atom do
      constraints(one_of: [:function, :class, :module, :block, :expression])
    end

    attribute(:start_line, :integer)
    attribute(:end_line, :integer)

    # Lazy-loaded AST
    attribute :ast, :map do
      description("AST fragment, loaded on demand")
    end

    attribute(:token_count, :integer)

    attribute :compressed_ast, :map do
      description("Optimized AST for AI consumption")
    end

    attribute(:cache_key, :string)
    attribute(:cached_until, :utc_datetime_usec)
  end

  relationships do
    belongs_to :working_set, Lang.Workspace.WorkingSet
    belongs_to :symbol, Lang.Workspace.Symbol
  end

  actions do
    defaults([:create, :read])

    read :get_or_create do
      argument :file_path, :string
      # {start, end}
      argument :start_line, :integer
      argument :end_line, :integer

      prepare(fn query, context ->
        file_path = context.arguments.file_path
        start_line = context.arguments.start_line
        end_line = context.arguments.end_line

        query
        |> Ash.Query.filter(%{
          file_path: file_path,
          start_line: start_line,
          end_line: end_line
        })
        |> Ash.Query.limit(1)
      end)
    end

    create :extract_and_optimize do
      accept([:file_path, :start_line, :end_line, :fragment_type])

      change(fn changeset, _context ->
        file_path = Ash.Changeset.get_attribute(changeset, :file_path)
        start_line = Ash.Changeset.get_attribute(changeset, :start_line)
        end_line = Ash.Changeset.get_attribute(changeset, :end_line)

        # Use the Rust NIF to parse the fragment
        case Lang.Native.TreeParser.extract_fragment(file_path, start_line, end_line) do
          {:ok, fragment} ->
            # Build cache key from file content hash and line range
            cache_key = generate_cache_key(file_path, start_line, end_line)

            # Generate token counts
            token_count = count_tokens(fragment.content)

            # Compress the AST via the TreeParser NIF
            {:ok, compressed} = Lang.Native.TreeParser.compress_ast(fragment.ast)

            changeset
            |> Ash.Changeset.change_attribute(:ast, fragment.ast)
            |> Ash.Changeset.change_attribute(:token_count, token_count)
            |> Ash.Changeset.change_attribute(:compressed_ast, compressed)
            |> Ash.Changeset.change_attribute(:cache_key, cache_key)
            |> Ash.Changeset.change_attribute(:cached_until, expiry_time())

          {:error, reason} ->
            # Log error and return unchanged
            require Logger
            Logger.error("Failed to extract fragment: #{inspect(reason)}")
            changeset
        end
      end)
    end

    # Custom action to get or create a fragment
    read :get_or_create_fragment do
      argument :file_path, :string
      # {start, end}
      argument :start_line, :integer
      argument :end_line, :integer

      # First try to find an existing fragment
      prepare(fn query, context ->
        file_path = context.arguments.file_path
        start_line = context.arguments.start_line
        end_line = context.arguments.end_line

        query
        |> Ash.Query.filter(%{
          file_path: file_path,
          start_line: start_line,
          end_line: end_line
        })
        |> Ash.Query.limit(1)
      end)

      # If no fragment is found, create a new one
      after_action(fn result, context ->
        case result do
          # If fragment found, return it
          {:ok, [fragment]} when is_map(fragment) ->
            {:ok, fragment}

          # If no fragment found, create a new one
          {:ok, []} ->
            Lang.Workspace.Fragment.extract_and_optimize(%{
              file_path: context.arguments.file_path,
              start_line: context.arguments.start_line,
              end_line: context.arguments.end_line,
              fragment_type:
                detect_fragment_type(
                  context.arguments.file_path,
                  context.arguments.start_line,
                  context.arguments.end_line
                )
            })

          # Pass through any errors
          error ->
            error
        end
      end)
    end
  end

  code_interface do
    define(:extract, action: :extract_and_optimize)
    define(:get_cached_or_create, action: :get_or_create, args: [:file_path])

    define(:get_or_create_fragment,
      action: :get_or_create_fragment,
      args: [:file_path]
      # args: [:file_path, :line_range]
    )
  end

  # Redis configuration
  # Short TTL for fragments - 5 minutes
  attributes do
    attribute(:ttl, :integer, public?: false, default: 300)
  end

  identities do
    identity(:by_cache_key, [:cache_key])
    identity(:by_location, [:file_path, :start_line, :end_line])
  end

  # Private helper functions

  defp detect_fragment_type(file_path, _start_line, _end_line) do
    # Use the Rust NIF to detect the fragment type
    # This is a placeholder
    case Path.extname(file_path) do
      ".ex" -> :function
      ".exs" -> :function
      ".rs" -> :function
      ".js" -> :function
      ".ts" -> :class
      ".py" -> :function
      _ -> :block
    end
  end

  defp generate_cache_key(file_path, start_line, end_line) do
    # Hash the file path and line range
    content_hash =
      case Lang.Native.FSScanner.file_hash(file_path) do
        {:ok, hash} -> hash
        _ -> :crypto.hash(:md5, file_path) |> Base.encode16(case: :lower)
      end

    "#{content_hash}:#{start_line}-#{end_line}"
  end

  defp count_tokens(content) do
    # Use a tokenizer to count tokens
    # This is a placeholder
    String.length(content || "") |> div(4) |> max(1)
  end

  defp expiry_time do
    # Set expiry 5 minutes from now
    DateTime.utc_now() |> DateTime.add(300, :second)
  end
end
