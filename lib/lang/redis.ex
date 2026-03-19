defmodule Lang.Redis do
  @moduledoc """
  Thin wrapper around Redix for convenience.
  """

  @name Lang.Redis

  def cmd(command), do: Redix.command(@name, command)
  def pipeline(commands) when is_list(commands), do: Redix.pipeline(@name, commands)

  def get(key) when is_binary(key), do: cmd(["GET", key])

  def setex(key, ttl, value) when is_binary(key) and is_integer(ttl),
    do: cmd(["SETEX", key, ttl, value])

  def incr(key) when is_binary(key), do: cmd(["INCR", key])
  def expire(key, ttl) when is_binary(key) and is_integer(ttl), do: cmd(["EXPIRE", key, ttl])

  @doc """
  Check if named Redix connection is available.
  """
  def available? do
    case Process.whereis(@name) do
      pid when is_pid(pid) -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
