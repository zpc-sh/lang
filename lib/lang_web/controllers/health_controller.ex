defmodule LangWeb.HealthController do
  use LangWeb, :controller

  def check(conn, _params) do
    health_status = get_health_status()

    case health_status.status do
      :ok ->
        conn
        |> put_status(:ok)
        |> json(health_status)

      :degraded ->
        conn
        |> put_status(:ok)
        |> json(health_status)

      :error ->
        conn
        |> put_status(:service_unavailable)
        |> json(health_status)
    end
  end

  defp get_health_status do
    checks = %{
      database: check_database(),
      redis: check_redis(),
      disk_space: check_disk_space(),
      memory: check_memory()
    }

    failed_checks =
      checks
      |> Enum.filter(fn {_name, %{status: status}} -> status == :error end)
      |> Enum.map(fn {name, _} -> name end)

    degraded_checks =
      checks
      |> Enum.filter(fn {_name, %{status: status}} -> status == :warning end)
      |> Enum.map(fn {name, _} -> name end)

    overall_status =
      cond do
        length(failed_checks) > 0 -> :error
        length(degraded_checks) > 0 -> :degraded
        true -> :ok
      end

    %{
      status: overall_status,
      timestamp: DateTime.utc_now(),
      version: Application.spec(:lang, :vsn) |> to_string(),
      uptime: get_uptime(),
      checks: checks,
      failed_checks: failed_checks,
      degraded_checks: degraded_checks
    }
  end

  defp check_database do
    try do
      case Ecto.Adapters.SQL.query(Lang.Repo, "SELECT 1", []) do
        {:ok, _} -> %{status: :ok, message: "Database connection healthy"}
        {:error, reason} -> %{status: :error, message: "Database error: #{inspect(reason)}"}
      end
    rescue
      exception -> %{status: :error, message: "Database exception: #{inspect(exception)}"}
    end
  end

  defp check_redis do
    try do
      redis_url = Application.get_env(:lang, :redis_url)

      case Redix.command(:redix, ["PING"]) do
        {:ok, "PONG"} -> %{status: :ok, message: "Redis connection healthy"}
        {:error, reason} -> %{status: :error, message: "Redis error: #{inspect(reason)}"}
        _ -> %{status: :error, message: "Redis unexpected response"}
      end
    rescue
      exception -> %{status: :error, message: "Redis exception: #{inspect(exception)}"}
    catch
      :exit, reason -> %{status: :error, message: "Redis connection failed: #{inspect(reason)}"}
    end
  end

  defp check_disk_space do
    try do
      case :disksup.get_disk_data() do
        [{_, kb_size, capacity}] when capacity < 90 ->
          %{
            status: :ok,
            message: "Disk usage: #{capacity}%",
            details: %{size_kb: kb_size, usage_percent: capacity}
          }

        [{_, kb_size, capacity}] when capacity < 95 ->
          %{
            status: :warning,
            message: "Disk usage high: #{capacity}%",
            details: %{size_kb: kb_size, usage_percent: capacity}
          }

        [{_, kb_size, capacity}] ->
          %{
            status: :error,
            message: "Disk usage critical: #{capacity}%",
            details: %{size_kb: kb_size, usage_percent: capacity}
          }

        _ ->
          %{status: :warning, message: "Could not determine disk usage"}
      end
    rescue
      _ -> %{status: :warning, message: "Disk monitoring unavailable"}
    end
  end

  defp check_memory do
    try do
      memory_data = :erlang.memory()
      total = Keyword.get(memory_data, :total, 0)
      processes = Keyword.get(memory_data, :processes, 0)
      system = Keyword.get(memory_data, :system, 0)

      total_mb = div(total, 1024 * 1024)

      cond do
        total_mb < 2048 ->
          %{
            status: :ok,
            message: "Memory usage: #{total_mb}MB",
            details: %{
              total_mb: total_mb,
              processes_mb: div(processes, 1024 * 1024),
              system_mb: div(system, 1024 * 1024)
            }
          }

        total_mb < 4096 ->
          %{
            status: :warning,
            message: "High memory usage: #{total_mb}MB",
            details: %{
              total_mb: total_mb,
              processes_mb: div(processes, 1024 * 1024),
              system_mb: div(system, 1024 * 1024)
            }
          }

        true ->
          %{
            status: :error,
            message: "Critical memory usage: #{total_mb}MB",
            details: %{
              total_mb: total_mb,
              processes_mb: div(processes, 1024 * 1024),
              system_mb: div(system, 1024 * 1024)
            }
          }
      end
    rescue
      _ -> %{status: :warning, message: "Memory monitoring unavailable"}
    end
  end

  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_seconds = div(uptime_ms, 1000)

    days = div(uptime_seconds, 86400)
    hours = div(rem(uptime_seconds, 86400), 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)
    seconds = rem(uptime_seconds, 60)

    "#{days}d #{hours}h #{minutes}m #{seconds}s"
  end
end
