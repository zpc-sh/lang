defmodule Lang.Dev.FSWatch.Pipeline do
  @moduledoc """
  Runs an FS watch event through a configurable middleware pipeline.

  Configuration (dev.exs, etc.):

      config :lang, :fswatcher_pipeline,
        middlewares: [
          Lang.Dev.FSWatch.MW.FilterKinds,
          {Lang.Dev.FSWatch.MW.FormatLine, color: true}
        ]

  If not configured, a sensible default is used.
  """

  @type event :: %{name: atom(), kind: atom(), path: String.t(), topic: String.t()}

  @spec run(event(), map()) :: iodata() | nil
  def run(event, overrides \\ %{}) do
    {mods, base_opts} = load_config()
    # Allow overrides to inject a one-off middleware list
    {mods, overrides} =
      case Map.pop(overrides, :middlewares) do
        {nil, o} -> {mods, o}
        {mw, o} -> {normalize(mw), o}
      end

    opts = Map.merge(base_opts, overrides)
    do_run(event, opts, mods)
  end

  defp load_config do
    cfg = Application.get_env(:lang, :fswatcher_pipeline, [])
    mws = Keyword.get(cfg, :middlewares, default_middlewares())
    # Allow a top-level :kinds or :color to be merged as defaults
    base = cfg |> Enum.into(%{})
    {normalize(mws), Map.drop(base, [:middlewares])}
  end

  defp default_middlewares do
    [
      Lang.Dev.FSWatch.MW.FilterKinds,
      {Lang.Dev.FSWatch.MW.FormatLine, color: true}
    ]
  end

  defp normalize(list) do
    Enum.map(list, fn
      {mod, opts} when is_atom(mod) and is_list(opts) -> {mod, Enum.into(opts, %{})}
      mod when is_atom(mod) -> {mod, %{} }
    end)
  end

  defp do_run(_event, _opts, []), do: nil
    
  defp do_run(event, opts, [{mod, mw_opts} | rest]) do
    merged = Map.merge(mw_opts, opts)
    case mod.handle(event, merged) do
      {:ok, ev, new_opts} -> do_run(ev, new_opts, rest)
      {:emit, io} -> io
      :skip -> nil
    end
  end
end
