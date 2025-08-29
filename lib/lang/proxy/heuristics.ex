defmodule Lang.Proxy.Heuristics do
  @moduledoc """
  Lightweight, in-memory heuristics for request plausibility.

  Goals:
  - Detect suspicious context switches (e.g., from long text-only chat to filesystem/ssh)
  - Nudge callers to explicitly override when switching sensitive surfaces
  - Keep fast and stateless enough to run in request path

  Storage: ETS table with sliding window of recent events per session_id (or user/org fallback).
  This is a soft guard; authoritative policy should be enforced separately.
  """

  @table :proxy_activity
  @window_sec 3600
  @minutes 60

  @type category :: :text | :lsp | :mcp | :ssh | :fs | :ai | :other

  def ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, read_concurrency: true])
      _ -> @table
    end
  end

  @doc """
  Pre-check a request. Returns :ok or {:error, {:heuristic_block, reason}}.
  """
  def precheck(env, ctx) do
    ensure_table()

    session_id = extract_session_id(env, ctx)
    category = classify(env)
    now = System.system_time(:second)

    with {:ok, stats} <- stats(session_id, now) do
      if block?(category, stats) do
        {:error, {:heuristic_block, hint(category, stats)}}
      else
        :ok
      end
    else
      _ -> :ok
    end
  end

  @doc """
  Record a request activity if allowed. Cheap best-effort.
  """
  def record(env, ctx) do
    ensure_table()
    session_id = extract_session_id(env, ctx)
    category = classify(env)
    now = System.system_time(:second)

    if Lang.Redis.available?() do
      bucket = minute_bucket(now)
      try do
        total_key = redis_key(session_id, bucket, :total)
        text_key = redis_key(session_id, bucket, :text)
        cmds =
          case category do
            :text -> [
              ["INCR", total_key],
              ["EXPIRE", total_key, Integer.to_string(@window_sec)],
              ["INCR", text_key],
              ["EXPIRE", text_key, Integer.to_string(@window_sec)]
            ]
            _ -> [
              ["INCR", total_key],
              ["EXPIRE", total_key, Integer.to_string(@window_sec)],
              ["SETEX", last_non_key(session_id), Integer.to_string(@window_sec), Integer.to_string(now)]
            ]
          end

        _ = Lang.Redis.pipeline(cmds)
      rescue
        _ -> :ets.insert(@table, {session_id, now, category})
      end
    else
      :ets.insert(@table, {session_id, now, category})
    end

    :ok
  end

  defp extract_session_id(env, ctx) do
    params = env.params || %{}
    cond do
      is_binary(params["session_id"]) -> params["session_id"]
      ctx[:current_user] && ctx[:current_org] -> "user:" <> ctx.current_user.id <> ":org:" <> ctx.current_org.id
      ctx[:current_user] -> "user:" <> ctx.current_user.id
      true -> "anon"
    end
  end

  defp classify(%{service: :ai, method: method}) when is_binary(method) do
    if String.starts_with?(method, "lang.chat.") or String.starts_with?(method, "lang.text.") do
      :text
    else
      :ai
    end
  end

  defp classify(%{service: :lsp}), do: :lsp
  defp classify(%{service: :ssh}), do: :ssh
  defp classify(%{service: :telnet}), do: :ssh
  defp classify(%{service: :fs}), do: :fs
  defp classify(_), do: :other

  defp stats(session_id, now) do
    # Try Redis minute buckets first
    if Lang.Redis.available?() do
      try do
        buckets = for i <- 0..(@minutes - 1), do: minute_bucket(now - i * 60)
        total_keys = Enum.map(buckets, &redis_key(session_id, &1, :total))
        text_keys = Enum.map(buckets, &redis_key(session_id, &1, :text))
        cmds = Enum.map(total_keys ++ text_keys, fn k -> ["GET", k] end)
        {:ok, results} = Lang.Redis.pipeline(cmds)
        {total_vals, text_vals} = Enum.split(results, length(total_keys))
        total = sum_vals(total_vals)
        text = sum_vals(text_vals)

        last_non =
          case Lang.Redis.get(last_non_key(session_id)) do
            {:ok, nil} -> nil
            {:ok, v} when is_binary(v) -> String.to_integer(v)
            _ -> nil
          end

        {:ok, %{total: total, text: text, last_non_text_at: last_non}}
      rescue
        _ -> ets_stats(session_id, now)
      end
    else
      ets_stats(session_id, now)
    end
  end

  defp ets_stats(session_id, now) do
      # ETS fallback
      window_start = now - @window_sec
      rows = :ets.lookup(@table, session_id)
      {total, text, last_non_text_at} =
        rows
        |> Enum.reduce({0, 0, nil}, fn {_sid, ts, cat}, {tot, txt, last_non} ->
          if ts >= window_start do
            new_tot = tot + 1
            new_txt = if cat == :text, do: txt + 1, else: txt
            new_last_non = if cat != :text, do: max((last_non || 0), ts), else: last_non
            {new_tot, new_txt, new_last_non}
          else
            {tot, txt, last_non}
          end
        end)

      {:ok, %{total: total, text: text, last_non_text_at: last_non_text_at}}
  end

  # Heuristic: if user has been text-only for an hour and attempts FS/SSH/LSP, block softly
  defp block?(cat, %{total: total, text: text, last_non_text_at: last_non})
       when cat in [:fs, :ssh, :lsp] do
    cond do
      total >= 10 and text / max(total, 1) >= 0.9 and (last_non || 0) < (System.system_time(:second) - 3600) -> true
      true -> false
    end
  end

  defp block?(_cat, _), do: false

  defp hint(cat, _stats) do
    case cat do
      :fs -> "suspicious context switch to filesystem after long text activity"
      :ssh -> "suspicious context switch to ssh after long text activity"
      :lsp -> "suspicious context switch to lsp after long text activity"
      _ -> "suspicious context switch"
    end
  end

  defp minute_bucket(ts_sec), do: div(ts_sec, 60)
  defp redis_key(session_id, bucket, kind), do: "proxy:act:" <> session_id <> ":" <> to_string(bucket) <> ":" <> to_string(kind)
  defp last_non_key(session_id), do: "proxy:last_non_text:" <> session_id
  defp sum_vals(vals) do
    vals
    |> Enum.reduce(0, fn
      {:ok, v}, acc when is_binary(v) -> acc + String.to_integer(v)
      _other, acc -> acc
    end)
  end
end
