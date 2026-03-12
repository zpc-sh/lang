defmodule Lang.Dev.FSWatch.Util do
  @moduledoc """
  Utilities for formatting and filtering FS watcher events.

  Shared by FS watcher logger and Mix tasks to keep output consistent.
  """

  @type kind :: :created | :modified | :deleted | atom()

  @doc """
  Returns true if the event kind is allowed by the optional filter list.
  If `kinds` is nil or an empty list, all kinds are allowed.
  """
  @spec allow_kind?(kind(), nil | [kind()]) :: boolean()
  def allow_kind?(_kind, nil), do: true
  def allow_kind?(_kind, []), do: true
  def allow_kind?(kind, kinds) when is_list(kinds), do: Enum.member?(kinds, kind)

  @doc """
  Returns an ANSI color sequence for a given kind.
  """
  @spec color_for(kind()) :: [iodata()]
  def color_for(:created), do: [IO.ANSI.green()]
  def color_for(:modified), do: [IO.ANSI.yellow()]
  def color_for(:deleted), do: [IO.ANSI.red()]
  def color_for(_), do: []

  @doc """
  Formats an event line with optional color.
  """
  @spec format_event(atom(), kind(), String.t(), boolean()) :: iodata()
  def format_event(name, kind, path, color? \\ true) do
    rel = relative(path)
    if color? do
      [color_for(kind), "[fswatch] ", inspect(name), " ", to_string(kind), ": ", rel, IO.ANSI.reset()]
    else
      ["[fswatch] ", inspect(name), " ", to_string(kind), ": ", rel]
    end
  end

  @doc """
  Make a path relative to CWD for concise output.
  """
  @spec relative(String.t()) :: String.t()
  def relative(path) do
    root = File.cwd!()
    case Path.relative_to_cwd(path) do
      ^path -> Path.relative_to(path, root)
      rel -> rel
    end
  end
end

