defmodule JsonldEx.Diff do
  @moduledoc """
  High-performance JSON-LD diff algorithms with multiple strategies:
  
  1. **CRDT-based operational diff** - For concurrent editing scenarios
  2. **Structural diff** - jsondiffpatch-style human-readable changes  
  3. **Semantic graph diff** - JSON-LD aware diffing preserving semantic meaning
  """

  alias JsonldEx.Diff.{Operational, Structural, Semantic}

  @type diff_strategy :: :operational | :structural | :semantic
  @type diff_options :: [
    strategy: diff_strategy(),
    include_moves: boolean(),
    array_diff: :lcs | :simple,
    semantic_normalize: boolean()
  ]

  @doc """
  Compute diff between two JSON-LD documents using specified strategy.
  
  ## Strategies
  
  - `:operational` - CRDT-based for concurrent editing
  - `:structural` - Human-readable jsondiffpatch-style deltas
  - `:semantic` - JSON-LD graph-aware semantic diffing
  
  ## Examples
  
      iex> old = %{"@context" => "https://schema.org/", "name" => "John"}
      iex> new = %{"@context" => "https://schema.org/", "name" => "Jane"}
      iex> JsonldEx.Diff.diff(old, new, strategy: :structural)
      {:ok, %{"name" => ["John", "Jane"]}}
  """
  @spec diff(map(), map(), diff_options()) :: {:ok, map()} | {:error, term()}
  def diff(old, new, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :structural)
    
    case strategy do
      :operational -> Operational.diff(old, new, opts)
      :structural -> Structural.diff(old, new, opts)
      :semantic -> Semantic.diff(old, new, opts)
      _ -> {:error, {:invalid_strategy, strategy}}
    end
  end

  @doc """
  Apply a diff patch to a JSON-LD document.
  """
  @spec patch(map(), map(), diff_options()) :: {:ok, map()} | {:error, term()}
  def patch(document, patch, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :structural)
    
    case strategy do
      :operational -> Operational.patch(document, patch, opts)
      :structural -> Structural.patch(document, patch, opts) 
      :semantic -> Semantic.patch(document, patch, opts)
      _ -> {:error, {:invalid_strategy, strategy}}
    end
  end

  @doc """
  Check if a patch is valid for a document.
  """
  @spec validate_patch(map(), map(), diff_options()) :: {:ok, boolean()} | {:error, term()}
  def validate_patch(document, patch, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :structural)
    
    case strategy do
      :operational -> Operational.validate_patch(document, patch, opts)
      :structural -> Structural.validate_patch(document, patch, opts)
      :semantic -> Semantic.validate_patch(document, patch, opts)
      _ -> {:error, {:invalid_strategy, strategy}}
    end
  end

  @doc """
  Merge multiple diffs into a single diff.
  Useful for combining concurrent edits.
  """
  @spec merge_diffs([map()], diff_options()) :: {:ok, map()} | {:error, term()}
  def merge_diffs(diffs, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :operational)
    
    case strategy do
      :operational -> Operational.merge_diffs(diffs, opts)
      :structural -> Structural.merge_diffs(diffs, opts)
      :semantic -> Semantic.merge_diffs(diffs, opts)
      _ -> {:error, {:invalid_strategy, strategy}}
    end
  end

  @doc """
  Compute the inverse of a diff (undo operation).
  """
  @spec inverse(map(), diff_options()) :: {:ok, map()} | {:error, term()}
  def inverse(patch, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :structural)
    
    case strategy do
      :operational -> Operational.inverse(patch, opts)
      :structural -> Structural.inverse(patch, opts)
      :semantic -> Semantic.inverse(patch, opts)
      _ -> {:error, {:invalid_strategy, strategy}}
    end
  end
end