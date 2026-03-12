defmodule MarkdownLd.Diff.Stream do
  @moduledoc """
  Streaming diff coordinator.

  Splits documents into chunks, computes per-chunk patches using the top-level
  `MarkdownLd.diff/3`, and emits `MarkdownLd.Diff.StreamEvent` sequences suitable
  for real-time transport. Includes a basic applier to reconstruct target text
  from an initial snapshot and a sequence of chunk patches.
  """

  alias MarkdownLd.Diff

  @type chunk_id :: non_neg_integer()
  @type chunk :: {chunk_id(), String.t(), String.t()}

  @doc """
  Split a markdown string into content chunks.

  Strategies:
  - `:paragraphs` (default): split by blank lines, group up to `:max_paragraphs`.
  - `:headings`: start a new chunk at headings. Use `:heading_level` (1..6)
    to start chunks at that level only (default: 1). Subheadings are included
    in the same chunk until the next heading of that level.
  """
  @spec chunk(String.t(), keyword()) :: [chunk()]
  def chunk(text, opts \\ []) do
    case Keyword.get(opts, :chunk_strategy, :paragraphs) do
      :paragraphs -> chunk_paragraphs(text, opts)
      :headings -> chunk_headings(text, opts)
      other -> raise ArgumentError, "unknown chunk_strategy: #{inspect(other)}"
    end
  end

  defp chunk_paragraphs(text, opts) do
    max_paragraphs = Keyword.get(opts, :max_paragraphs, 8)
    paragraphs = paragraphs(text)

    paragraphs
    |> Enum.chunk_every(max_paragraphs)
    |> Enum.with_index()
    |> Enum.map(fn {paras, idx} ->
      content = Enum.join(paras, "\n\n")
      stable_id = stable_id_for(paras)
      {idx, content, stable_id}
    end)
  end

  defp chunk_headings(text, opts) do
    lines = String.split(text, "\n", trim: false)
    level = Keyword.get(opts, :heading_level, 1)
    sections = split_by_headings(lines, level)

    sections
    |> Enum.with_index()
    |> Enum.map(fn {{heading_line, body_lines}, idx} ->
      content = Enum.join(Enum.reject([heading_line | body_lines], &is_nil/1), "\n")
      stable_id = stable_id_for_heading(heading_line)
      {idx, content, stable_id}
    end)
  end

  defp split_by_headings(lines, level) do
    {sections, current} =
      Enum.reduce(lines, {[], {nil, []}}, fn line, {acc, {cur_heading, cur_body}} ->
        case heading_meta(line) do
          {lvl, _text} when is_integer(lvl) and lvl <= level ->
            acc =
              if cur_heading == nil and cur_body != [] do
                # Preface before first heading becomes its own section
                acc ++ [{nil, cur_body}]
              else
                acc
              end

            {acc ++ [{line, []}], {line, []}}

          _ ->
            {acc, {cur_heading, cur_body ++ [line]}}
        end
      end)

    # append trailing body to last section
    case sections do
      [] ->
        if Enum.any?(current |> elem(1), &(&1 != nil and &1 != "")) do
          [{nil, elem(current, 1)}]
        else
          []
        end

      _ ->
        {last_heading, last_body} = current

        if last_heading != nil or last_body != [] do
          # merge body to last section
          List.update_at(sections, -1, fn {h, b} -> {h, b ++ last_body} end)
        else
          sections
        end
    end
  end

  defp paragraphs(text) do
    text
    |> String.split(~r/(?:\r?\n){2,}/, trim: false)
    |> Enum.map(&String.trim_trailing/1)
  end

  @doc """
  Produce a finite list of `Diff.StreamEvent` from old->new content.

  Emits:
  - :init_snapshot with from_rev
  - zero or more :chunk_patch events (one per new chunk index)
  - :complete with to_rev
  """
  @spec emit(String.t(), String.t(), keyword()) :: [Diff.StreamEvent.t()]
  def emit(old_text, new_text, opts \\ []) do
    from_rev = Keyword.get(opts, :from_rev, content_rev(old_text))
    to_rev = Keyword.get(opts, :to_rev, content_rev(new_text))
    doc = Keyword.get(opts, :doc, nil)

    old_chunks = chunk(old_text, opts)
    new_chunks = chunk(new_text, opts)

    # Align by stable_id first. If using heading chunking, optionally fuzzy-match renamed headings.
    old_by_sid = Map.new(old_chunks, fn {cid, content, sid} -> {sid, {cid, content}} end)
    heading_mode? = Keyword.get(opts, :chunk_strategy, :paragraphs) == :headings
    threshold = Keyword.get(opts, :rename_match_threshold, 0.7)

    old_heading_index =
      if heading_mode? do
        Enum.map(old_chunks, fn {cid, content, sid} -> {sid, heading_text_from_chunk(content), cid, content} end)
      else
        []
      end

    {aligned, _used} =
      Enum.reduce(new_chunks, {[], MapSet.new()}, fn {ncid, ncontent, nsid}, {acc, used} ->
        case old_by_sid[nsid] do
          {ocid, ocontent} -> {[{ncid, ncontent, nsid, ocontent, ocid} | acc], MapSet.put(used, nsid)}
          nil ->
            if heading_mode? do
              ntext = heading_text_from_chunk(ncontent)
              {match_sid, ocid, ocontent} = best_heading_match(ntext, old_heading_index, used, threshold)
              if match_sid do
                {[{ncid, ncontent, nsid, ocontent, ocid} | acc], MapSet.put(used, match_sid)}
              else
                {_, ocontent, _} = Enum.find(old_chunks, fn {cid, _, _} -> cid == ncid end) || {nil, "", nil}
                {[{ncid, ncontent, nsid, ocontent, ncid} | acc], used}
              end
            else
              {_, ocontent, _} = Enum.find(old_chunks, fn {cid, _, _} -> cid == ncid end) || {nil, "", nil}
              {[{ncid, ncontent, nsid, ocontent, ncid} | acc], used}
            end
        end
      end)
      |> then(fn {acc, used} -> {Enum.reverse(acc), used} end)

    init = %Diff.StreamEvent{type: :init_snapshot, doc: doc, rev: from_rev, meta: %{}}

    patch_events =
      aligned
      |> Enum.map(fn {cid, ncontent, sid, ocontent, _ocid} ->
        {:ok, patch} = MarkdownLd.diff(ocontent, ncontent)

        %Diff.StreamEvent{
          type: :chunk_patch,
          doc: doc,
          rev: nil,
          chunk_id: cid,
          patch: patch,
          meta: %{stable_id: sid}
        }
      end)

    # deletions: old chunks whose stable_id not present in new
    new_sids = MapSet.new(Enum.map(new_chunks, fn {_, _, sid} -> sid end))

    delete_events =
      old_chunks
      |> Enum.reject(fn {_, _, sid} -> MapSet.member?(new_sids, sid) end)
      |> Enum.map(fn {cid, ocontent, sid} ->
        {:ok, patch} = MarkdownLd.diff(ocontent, "")

        %Diff.StreamEvent{
          type: :chunk_patch,
          doc: doc,
          rev: nil,
          chunk_id: cid,
          patch: patch,
          meta: %{stable_id: sid}
        }
      end)

    complete = %Diff.StreamEvent{type: :complete, doc: doc, rev: to_rev, meta: %{}}

    [init] ++ patch_events ++ delete_events ++ [complete]
  end

  @doc """
  Apply a stream of events to an initial document text and reconstruct the
  resulting document. Only supports events produced by `emit/3`.
  """
  @spec apply_events(String.t(), [Diff.StreamEvent.t()], keyword()) :: {:ok, String.t()}
  def apply_events(old_text, events, opts \\ []) do
    chunks = chunk(old_text, opts)
    chunk_map = Map.new(chunks, fn {cid, content, _sid} -> {cid, content} end)

    final_map =
      Enum.reduce(events, chunk_map, fn
        %Diff.StreamEvent{type: :chunk_patch, chunk_id: cid, patch: patch}, acc ->
          # Apply patch by re-materializing the chunk using changes; since the patch
          # is generated from old->new chunk texts, we can just trust patch.to rev
          # and reconstruct by applying the changes to old text.
          old = Map.get(acc, cid, "")
          new = MarkdownLd.Diff.Apply.apply_to_text(old, patch)
          Map.put(acc, cid, new)

        _other, acc ->
          acc
      end)

    # Reassemble in order of chunk_id
    result =
      final_map
      |> Enum.sort_by(fn {cid, _} -> cid end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.join("\n\n")

    {:ok, result}
  end

  defp stable_id_for(paragraphs) do
    anchor =
      paragraphs
      |> Enum.find(fn p -> String.trim(p) != "" end)
      |> case do
        nil -> ""
        p -> p |> String.slice(0, 80) |> String.downcase()
      end

    :crypto.hash(:sha256, anchor) |> Base.encode16(case: :lower) |> binary_part(0, 16)
  end

  defp heading_meta(line) do
    case Regex.run(~r/^(#+)\s+(.*)$/, line) do
      [_, hashes, text] -> {min(String.length(hashes), 6), text}
      _ -> nil
    end
  end

  defp stable_id_for_heading(nil), do: stable_id_for([""])

  defp stable_id_for_heading(heading_line) do
    {_lvl, text} = heading_meta(heading_line) || {nil, ""}

    slug =
      text
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{N}\s-]+/u, "")
      |> String.trim()
      |> String.replace(~r/\s+/, "-")

    base = if slug == "", do: "section", else: slug
    hash = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower) |> binary_part(0, 8)
    base <> "-" <> hash
  end

  defp content_rev(text) do
    :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
  end

  # patch application moved to MarkdownLd.Diff.Apply
  defp heading_text_from_chunk(content) do
    content
    |> String.split("
", parts: 2)
    |> List.first()
    |> case do
      nil -> ""
      line ->
        case heading_meta(line) do
          {_lvl, text} -> text
          _ -> ""
        end
    end
  end

  defp best_heading_match(ntext, old_index, used_set, threshold) do
    tokens_n = tokenize(ntext)
    old_index
    |> Enum.reject(fn {sid, _txt, _cid, _c} -> MapSet.member?(used_set, sid) end)
    |> Enum.map(fn {sid, otext, cid, content} ->
      {similarity(tokens_n, tokenize(otext)), sid, cid, content}
    end)
    |> Enum.sort_by(fn {score, _sid, _cid, _} -> -score end)
    |> case do
      [{score, sid, cid, content} | _] when score >= threshold -> {sid, cid, content}
      _ -> {nil, nil, nil}
    end
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}_\s]+/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> MapSet.new()
  end

  defp similarity(a, b) do
    inter = MapSet.size(MapSet.intersection(a, b))
    denom = MapSet.size(a) + MapSet.size(b)
    if denom == 0, do: 1.0, else: 2.0 * inter / denom
  end

end
