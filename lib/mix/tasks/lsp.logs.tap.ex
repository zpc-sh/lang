defmodule Mix.Tasks.Lsp.Logs.Tap do
  use Mix.Task

  @shortdoc "Tap Lang LSP measurement events via PubSub and print JSON"
  @moduledoc """
  Subscribes to AshEvents-style PubSub topics for LSP measurements and prints
  JSON lines for a limited duration, then exits.

  Examples:

      mix lsp.logs.tap                  # 20s on lsp:measurements:global
      mix lsp.logs.tap --seconds 10
      mix lsp.logs.tap --topic client:client_123
      mix lsp.logs.tap --topic method:lang.think.review_code --seconds 30 --out /tmp/lsp_tap.jsonl

  Topic options:
  - global (default)
  - client:<client_id>
  - method:<method>
  """

  @default_seconds 20

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(argv,
        strict: [seconds: :integer, topic: :string, out: :string],
        aliases: [s: :seconds, t: :topic, o: :out]
      )

    seconds = opts[:seconds] || @default_seconds
    topic = normalize_topic(opts[:topic] || "global")
    out = opts[:out]

    ensure_subscription(topic)

    deadline = System.monotonic_time(:millisecond) + seconds * 1000
    stream_loop(deadline, out)
  end

  defp normalize_topic("global"), do: "lsp:measurements:global"
  defp normalize_topic("client:" <> cid), do: "lsp:measurements:" <> cid
  defp normalize_topic("method:" <> method), do: "lsp:measurements:" <> method
  defp normalize_topic(other), do: other

  defp ensure_subscription(topic) do
    try do
      Phoenix.PubSub.subscribe(Lang.PubSub, topic)
      Mix.shell().info("Subscribed to #{topic}")
    rescue
      e -> Mix.raise("Failed to subscribe to #{topic}: #{inspect(e)}")
    end
  end

  defp stream_loop(deadline, out) do
    now = System.monotonic_time(:millisecond)
    if now >= deadline do
      :ok
    else
      timeout = max(0, deadline - now)
      receive do
        msg ->
          line = encode_line(msg)
          if out, do: append_file(out, line), else: IO.puts(line)
          stream_loop(deadline, out)
      after
        timeout -> :ok
      end
    end
  end

  defp encode_line(%{} = map), do: Jason.encode!(map)
  defp encode_line(other), do: Jason.encode!(%{message: inspect(other)})

  defp append_file(path, line) do
    File.write!(path, line <> "\n", [:append])
  end
end

