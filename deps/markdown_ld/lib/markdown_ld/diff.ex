defmodule MarkdownLd.Diff do
  @moduledoc """
  Data model and helpers for structure-aware Markdown diffs with JSON-LD semantics
  and collaborative editing support.

  This module defines:
  - Core diff primitives (blocks, inline, and JSON-LD semantic ops)
  - Patch and metadata for git-like workflows
  - Three-way merge result and conflict types
  - Streaming event schema for real-time updates

  Algorithms are intentionally minimal/stubbed; this is the foundation for
  future structural diffing and merge implementations.
  """

  @typedoc "Git-like content hash or revision identifier"
  @type rev() :: String.t()

  @typedoc "Path into a Markdown AST-like structure (e.g., [section_idx, block_idx, inline_idx])"
  @type path() :: [non_neg_integer()]

  @typedoc "Block type within Markdown"
  @type block_type() ::
          :heading
          | :paragraph
          | :list
          | :list_item
          | :code_block
          | :blockquote
          | :table
          | :thematic_break
          | :link
          | :image

  @typedoc "Inline segment classification"
  @type inline_type() :: :text | :em | :strong | :code | :link | :del | :ins

  @typedoc "JSON-LD triple-like edge"
  @type jsonld_triple() :: %{s: String.t(), p: String.t(), o: String.t()}

  @typedoc "Generic author metadata"
  @type author() :: %{id: String.t(), name: String.t() | nil}

  @typedoc "Timestamp in milliseconds since epoch"
  @type ts_ms() :: non_neg_integer()

  @typedoc "Common metadata captured on each change"
  @type meta() :: %{author: author() | nil, ts: ts_ms() | nil, message: String.t() | nil}

  defmodule Change do
    @moduledoc "Single change operation against a document"
    @enforce_keys [:id, :kind]
    defstruct [
      :id,
      :kind,
      :path,
      :block_type,
      :inline_type,
      :payload,
      :meta
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            kind:
              :insert_block
              | :delete_block
              | :update_block
              | :move_block
              | :insert_inline
              | :delete_inline
              | :update_inline
              | :jsonld_add
              | :jsonld_remove
              | :jsonld_update,
            path: MarkdownLd.Diff.path() | nil,
            block_type: MarkdownLd.Diff.block_type() | nil,
            inline_type: MarkdownLd.Diff.inline_type() | nil,
            payload: map() | nil,
            meta: MarkdownLd.Diff.meta() | nil
          }
  end

  defmodule Patch do
    @moduledoc "A set of changes with provenance"
    @enforce_keys [:id, :from, :to, :changes]
    defstruct [:id, :from, :to, :changes, :meta]

    @type t :: %__MODULE__{
            id: String.t(),
            from: MarkdownLd.Diff.rev(),
            to: MarkdownLd.Diff.rev(),
            changes: [MarkdownLd.Diff.Change.t()],
            meta: MarkdownLd.Diff.meta() | nil
          }
  end

  defmodule Conflict do
    @moduledoc "Represents a merge conflict on a specific path"
    @enforce_keys [:path, :reason]
    defstruct [:path, :reason, :ours, :theirs]

    @type reason() ::
            :same_segment_edit
            | :delete_vs_edit
            | :move_vs_edit
            | :order_conflict
            | :jsonld_semantic

    @type t :: %__MODULE__{
            path: MarkdownLd.Diff.path(),
            reason: reason(),
            ours: MarkdownLd.Diff.Change.t() | nil,
            theirs: MarkdownLd.Diff.Change.t() | nil
          }
  end

  defmodule MergeResult do
    @moduledoc "Outcome of a three-way merge"
    @enforce_keys [:base, :ours, :theirs]
    defstruct [:base, :ours, :theirs, :merged, :conflicts]

    @type t :: %__MODULE__{
            base: Patch.t(),
            ours: Patch.t(),
            theirs: Patch.t(),
            merged: Patch.t() | nil,
            conflicts: [Conflict.t()] | nil
          }
  end

  defmodule StreamEvent do
    @moduledoc "Streaming diff protocol events for real-time updates"
    @enforce_keys [:type]
    defstruct [
      :type,
      :doc,
      :rev,
      :chunk_id,
      :patch,
      :ack_of,
      :meta
    ]

    @type type() :: :init_snapshot | :chunk_patch | :ack | :complete

    @type t :: %__MODULE__{
            type: type(),
            doc: String.t() | nil,
            rev: MarkdownLd.Diff.rev() | nil,
            chunk_id: non_neg_integer() | nil,
            patch: Patch.t() | nil,
            ack_of: non_neg_integer() | nil,
            meta: MarkdownLd.Diff.meta() | nil
          }
  end

  # ——— Convenience constructors ———

  @doc "Create a basic change with generated id"
  @spec change(atom(), path() | nil, map()) :: Change.t()
  def change(kind, path, payload) when is_atom(kind) do
    %Change{id: new_id(), kind: kind, path: path, payload: payload}
  end

  @doc "Create a patch from -> to with supplied changes"
  @spec patch(rev(), rev(), [Change.t()], meta()) :: Patch.t()
  def patch(from, to, changes, meta \\ %{}) do
    %Patch{id: new_id(), from: from, to: to, changes: List.wrap(changes), meta: meta}
  end

  @doc "Detect naive conflicts between two sets of changes. Placeholder for richer logic."
  @spec detect_conflicts([Change.t()], [Change.t()]) :: [Conflict.t()]
  def detect_conflicts(ours, theirs) do
    # Extremely simple heuristic: conflict if same path and overlapping kinds that modify content
    ours
    |> Enum.flat_map(fn oc ->
      Enum.filter_map(theirs, fn tc -> conflicting?(oc, tc) end, fn tc ->
        %Conflict{path: oc.path || [], reason: classify(oc, tc), ours: oc, theirs: tc}
      end)
    end)
  end

  @doc "Three-way merge skeleton: returns merged patch if no conflicts, else conflicts."
  @spec three_way_merge(Patch.t(), Patch.t(), Patch.t()) :: MergeResult.t()
  def three_way_merge(base, ours, theirs) do
    conflicts = detect_conflicts(ours.changes, theirs.changes)

    case try_resolve_conflicts(conflicts) do
      {resolved, unresolved} when unresolved == [] ->
        pruned_ours = prune_conflicted(ours.changes, resolved)
        pruned_theirs = prune_conflicted(theirs.changes, resolved)
        merged_changes = pruned_ours ++ pruned_theirs ++ resolved
        %MergeResult{
          base: base,
          ours: ours,
          theirs: theirs,
          merged: %Patch{id: new_id(), from: base.from, to: ours.to, changes: merged_changes, meta: %{message: "auto-merged"}},
          conflicts: []
        }

      {resolved, unresolved} ->
        %MergeResult{base: base, ours: ours, theirs: theirs, merged: nil, conflicts: unresolved}
    end
  end

  @doc ~S"""
  Quick example

      iex> alias MarkdownLd.Diff
      iex> base = Diff.patch("rev0", "rev0", [], %{})
      iex> ours = Diff.patch("rev0", "rev1", [Diff.change(:insert_block, [0], %{text: "A"})], %{})
      iex> theirs = Diff.patch("rev0", "rev2", [Diff.change(:insert_block, [1], %{text: "B"})], %{})
      iex> result = Diff.three_way_merge(base, ours, theirs)
      iex> result.conflicts
      []
  """
  def __docs_example__, do: :ok

  # ——— Internals ———

  defp new_id do
    # Short, collision-resistant id for docs/tests; replace with ULID/UUID as needed
    Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
  end

  defp mutating_kind?(k) do
    k in [:insert_block, :delete_block, :update_block, :move_block, :insert_inline, :delete_inline,
          :update_inline, :jsonld_add, :jsonld_remove, :jsonld_update]
  end

  defp conflicting?(%Change{} = a, %Change{} = b) do
    mutating_kind?(a.kind) and mutating_kind?(b.kind) and (a.path || []) == (b.path || [])
  end

  defp classify(%Change{kind: ka}, %Change{kind: kb}) do
    cond do
      ka in [:delete_block, :delete_inline] or kb in [:delete_block, :delete_inline] -> :delete_vs_edit
      ka == :move_block or kb == :move_block -> :move_vs_edit
      ka in [:jsonld_add, :jsonld_remove, :jsonld_update] or kb in [:jsonld_add, :jsonld_remove, :jsonld_update] -> :jsonld_semantic
      true -> :same_segment_edit
    end
  end

  # ——— Conflict resolution helpers ———

  defp try_resolve_conflicts(conflicts) do
    Enum.reduce(conflicts, {[], []}, fn c, {resolved, unresolved} ->
      case resolve_conflict(c) do
        {:ok, change} -> {[change | resolved], unresolved}
        :conflict -> {resolved, [c | unresolved]}
      end
    end)
    |> then(fn {res, unres} -> {Enum.reverse(res), Enum.reverse(unres)} end)
  end

  defp resolve_conflict(%Conflict{reason: :same_segment_edit, path: path, ours: %Change{kind: :update_block, payload: po}, theirs: %Change{kind: :update_block, payload: pt}}) do
    before_o = po[:before]
    before_t = pt[:before]
    after_o = po[:after]
    after_t = pt[:after]

    cond do
      is_binary(after_o) and after_o == after_t ->
        {:ok, change(:update_block, path, %{type: po[:type], before: before_o, after: after_o, inline_ops: MarkdownLd.Diff.Inline.diff(before_o || "", after_o)})}

      is_binary(before_o) and before_o == before_t and is_binary(after_o) and is_binary(after_t) ->
        case resolve_text(before_o, after_o, after_t) do
          {:ok, merged} -> {:ok, change(:update_block, path, %{type: po[:type], before: before_o, after: merged, inline_ops: MarkdownLd.Diff.Inline.diff(before_o, merged)})}
          :conflict -> :conflict
        end

      true -> :conflict
    end
  end
  defp resolve_conflict(_), do: :conflict

  # Conservative text resolver: if one side is a strict/weak superset (substring
  # containment), prefer the longer; otherwise, leave as conflict.
  defp resolve_text(before, a, b) do
    cond do
      a == b -> {:ok, a}
      String.contains?(a, b) -> {:ok, a}
      String.contains?(b, a) -> {:ok, b}
      normalize_text(a) == normalize_text(b) -> {:ok, if(String.length(a) >= String.length(b), do: a, else: b)}
      true -> :conflict
    end
  end

  defp normalize_text(s) do
    s
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "")
  end

  defp prune_conflicted(changes, resolved_changes) do
    resolved_paths = MapSet.new(Enum.map(resolved_changes, & &1.path))
    Enum.reject(changes, fn ch -> MapSet.member?(resolved_paths, ch.path) end)
  end
end
