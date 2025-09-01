defmodule Lang.Dev.FSWatch.MW.Timestamp do
  @moduledoc """
  Adds a formatted timestamp to opts so downstream formatting middlewares can include it.

  Options:
  - :format -> Calendar strftime format (default "%H:%M:%S")
  - :key    -> opts key to store (default :timestamp_text)
  - :utc    -> boolean (default true), use UTC time
  """

  @behaviour Lang.Dev.FSWatch.Middleware

  @impl true
  def handle(event, opts) do
    fmt = Map.get(opts, :format, "%H:%M:%S")
    key = Map.get(opts, :key, :timestamp_text)
    use_utc = Map.get(opts, :utc, true)

    dt = if use_utc, do: DateTime.utc_now(), else: DateTime.now!(Calendar.get_time_zone_database())

    text =
      try do
        Calendar.strftime(dt, fmt)
      rescue
        _ -> DateTime.to_iso8601(dt)
      end

    {:ok, event, Map.put(opts, key, text)}
  end
end

