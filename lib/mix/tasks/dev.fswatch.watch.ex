defmodule Mix.Tasks.Dev.Fswatch.Watch do
  use Mix.Task
  @shortdoc "Stream FS events for a limited time with periodic summaries"

  @moduledoc """
  Subscribes to a PubSub topic (default: dev:fs:jsonld), prints events as they
  arrive, and periodically prints a summary.

      mix dev.fswatch.watch
      mix dev.fswatch.watch --topic dev:fs:docs --seconds 60 --interval 5

  Options:
    --topic     PubSub topic (default: dev:fs:jsonld)
    --seconds   Total duration to run in seconds (default: 60)
    --interval  Summary interval in seconds (default: 5)

  Notes:
  - Respects the repository guidelines by running for a bounded duration.
  - Use CTRL-C to interrupt sooner if needed.
  """

  @switches [topic: :string, seconds: :integer, interval: :integer, both: :boolean, kinds: :string]

  def run(args) do
    Mix.Task.run("app.start")
    {opts, _argv, _} = OptionParser.parse(args, switches: @switches)

    topics =
      cond do
        opts[:both] -> ["dev:fs:jsonld", "dev:fs:docs"]
        t = opts[:topic] -> [t]
        true -> ["dev:fs:jsonld"]
      end

    kinds = parse_kinds(opts[:kinds])
    seconds = opts[:seconds] || 60
    interval = opts[:interval] || 5

    preset = Application.get_env(:lang, :fswatcher_preset)
    ts_preset = Application.get_env(:lang, :fswatcher_timestamp, false)

    format =
      cond do
        opts[:json] -> :json
        opts[:align] -> {:align, opts[:cols]}
        preset in [:json, "json"] -> :json
        preset in [:align, "align"] -> {:align, opts[:cols]}
        true -> {:line, opts[:cols]}
      end

    color? = not (opts[:no_color] || false)
    ts? = (opts[:ts] || ts_preset || false)

    {:ok, pid} = Task.start_link(fn -> loop(topics, kinds, seconds, interval, format, color?, ts?) end)
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, _pid, _reason} -> :ok
    end
  end

  defp loop(topics, kinds, seconds, interval, format, color?, ts?) do
    Enum.each(topics, fn topic ->
      try do
        Phoenix.PubSub.subscribe(Lang.PubSub, topic)
      rescue
        _ -> :ok
      end
    end)

    deadline = System.monotonic_time(:millisecond) + seconds * 1_000
    next_summary = System.monotonic_time(:millisecond) + interval * 1_000

    counts = %{:created => 0, :modified => 0, :deleted => 0}
    total = 0

    IO.puts("[fswatch] watching topics=#{Enum.join(topics, ",")} for #{seconds}s (interval=#{interval}s)")

    loop_recv(topics, kinds, deadline, next_summary, interval, counts, total, format, color?, ts?)
  end

  defp loop_recv(topics, kinds, deadline, next_summary, interval, counts, total, format, color?, ts?) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      IO.puts("[fswatch] done topics=#{Enum.join(topics, ",")} total=#{total} by_kind=#{inspect(counts)}")
    else
      timeout = max(0, min(1_000, deadline - now))

      receive do
        {:fs_event, name, %{path: path, kind: kind}} ->
          if Lang.Dev.FSWatch.Util.allow_kind?(kind, kinds) do
            ev = %{name: name, kind: kind, path: path, topic: infer_topic(path, topics)}
            line = Lang.Dev.FSWatch.Pipeline.run(ev, %{kinds: kinds, color: true}) ||
                     Lang.Dev.FSWatch.Util.format_event(name, kind, path, true)
            IO.puts(IO.iodata_to_binary(line))
            counts = Map.update(counts, kind, 1, &(&1 + 1))
            total = total + 1
            loop_recv(topics, kinds, deadline, next_summary, interval, counts, total, format, color?, ts?)
          else
            loop_recv(topics, kinds, deadline, next_summary, interval, counts, total, format, color?, ts?)
          end

        _other ->
          loop_recv(topics, kinds, deadline, next_summary, interval, counts, total, format, color?, ts?)
      after
        timeout ->
          now2 = System.monotonic_time(:millisecond)
          if now2 >= next_summary do
            IO.puts("[fswatch] summary topics=#{Enum.join(topics, ",")} total=#{total} by_kind=#{inspect(counts)}")
            loop_recv(topics, kinds, deadline, now2 + interval * 1_000, interval, counts, total, format, color?, ts?)
          else
            loop_recv(topics, kinds, deadline, next_summary, interval, counts, total, format, color?, ts?)
          end
      end
    end
  end

  defp rel(path) do
    root = File.cwd!()
    case Path.relative_to_cwd(path) do
      ^path -> Path.relative_to(path, root)
      rel -> rel
    end
  end

  defp render(ev, kinds, :json, _color?, ts?) do
    Lang.Dev.FSWatch.Pipeline.run(ev, %{middlewares: [Lang.Dev.FSWatch.MW.FilterKinds, Lang.Dev.FSWatch.MW.JsonLine], kinds: kinds, timestamp: ts?})
  end

  defp render(ev, kinds, {:align, cols}, color?, ts?) do
    cols = cols || 80
    begin = [Lang.Dev.FSWatch.MW.FilterKinds]
    begin = begin ++ (if ts?, do: [Lang.Dev.FSWatch.MW.Timestamp], else: [])
    begin = begin ++ [{Lang.Dev.FSWatch.MW.Align, [color: color?, path_width: cols]}]
    Lang.Dev.FSWatch.Pipeline.run(ev, %{middlewares: begin, kinds: kinds, color: color?})
  end

  defp render(ev, kinds, {:line, _cols}, color?, ts?) do
    begin = [Lang.Dev.FSWatch.MW.FilterKinds]
    begin = begin ++ (if ts?, do: [Lang.Dev.FSWatch.MW.Timestamp], else: [])
    begin = begin ++ [{Lang.Dev.FSWatch.MW.FormatLine, [color: color?]}]
    Lang.Dev.FSWatch.Pipeline.run(ev, %{middlewares: begin, kinds: kinds, color: color?})
  end

  defp infer_topic(_path, [single]), do: single
  defp infer_topic(path, topics) do
    docs_dir = Lang.Dev.Config.docs_dir()
    if String.starts_with?(Path.expand(path), Path.expand(docs_dir)) do
      Enum.find(topics, &(&1 == "dev:fs:docs")) || List.first(topics)
    else
      Enum.find(topics, &(&1 == "dev:fs:jsonld")) || List.first(topics)
    end
  end

  defp parse_kinds(nil), do: nil
  defp parse_kinds(str) when is_binary(str) do
    str
    |> String.split([",", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_existing_atom/1)
  rescue
    _ -> nil
  end
end
