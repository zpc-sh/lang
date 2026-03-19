defmodule Lang.Dev.FSWatch.MW.Align do
  @moduledoc """
  Formats an event into aligned columns (name, kind, path) with optional color and truncation.

  Options:
  - :color       -> boolean (default true), use ANSI colors for kind
  - :name_width  -> integer (default 8)
  - :kind_width  -> integer (default 9)
  - :path_width  -> integer (default 80) maximum path width (truncated on the left)
  """

  @behaviour Lang.Dev.FSWatch.Middleware

  @impl true
  def handle(%{name: name, kind: kind, path: path}, opts) do
    color? = Map.get(opts, :color, true)
    ts = Map.get(opts, :timestamp_text)
    nw = Map.get(opts, :name_width, 8)
    kw = Map.get(opts, :kind_width, 9)
    pw = Map.get(opts, :path_width, 80)

    n = name |> to_string() |> String.pad_trailing(nw) |> String.slice(0, nw)
    k = kind |> to_string() |> String.pad_trailing(kw) |> String.slice(0, kw)
    p = path |> Lang.Dev.FSWatch.Util.relative() |> truncate_left(pw)

    line =
      [
        (if ts, do: [IO.ANSI.faint(), ts, IO.ANSI.reset(), " "], else: []),
        if(color?, do: [IO.ANSI.faint(), n, IO.ANSI.reset(), " ", Lang.Dev.FSWatch.Util.color_for(kind), k, IO.ANSI.reset(), "  "], else: [n, " ", k, "  "]),
        p
      ]

    {:emit, line}
  end

  defp truncate_left(str, max) when is_integer(max) and max > 0 do
    if String.length(str) <= max do
      str
    else
      "…" <> String.slice(str, -max + 1, max - 1)
    end
  end

  defp truncate_left(str, _), do: str
end
