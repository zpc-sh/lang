defmodule Lang.Dev.FSWatch.MW.FormatLine do
  @moduledoc """
  Formats an event into a single log line.

  Options:
  - :color -> boolean (default true), use ANSI colors
  """

  @behaviour Lang.Dev.FSWatch.Middleware

  @impl true
  def handle(%{name: name, kind: kind, path: path}, opts) do
    color? = Map.get(opts, :color, true)
    ts = Map.get(opts, :timestamp_text)
    base = Lang.Dev.FSWatch.Util.format_event(name, kind, path, color?)
    line = [IO.ANSI.faint(), ts, IO.ANSI.reset(), ' ' , base] if ts else base
    {:emit, line}
  end
end

