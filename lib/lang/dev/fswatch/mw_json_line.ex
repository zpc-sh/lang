defmodule Lang.Dev.FSWatch.MW.JsonLine do
  @moduledoc """
  Emits a JSON line for the event suitable for machine processing.

  Options: ignored; outputs a JSON object with keys: name, kind, path, topic
  """

  @behaviour Lang.Dev.FSWatch.Middleware

  @impl true
  def handle(%{name: name, kind: kind, path: path, topic: topic}, opts) do
    map = %{
      name: to_string(name),
      kind: to_string(kind),
      path: Lang.Dev.FSWatch.Util.relative(path),
      topic: topic
    }

    {:emit, Jason.encode_to_iodata!(map)}
  end
end

