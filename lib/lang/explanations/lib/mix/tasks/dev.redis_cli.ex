defmodule Mix.Tasks.Dev.RedisCli do
  @shortdoc "Print redis-cli command or run a PING"
  @moduledoc """
  Usage:
    mix dev.redis_cli            # prints interactive redis-cli command and PINGs
    mix dev.redis_cli --ping     # explicit PING
  """
  use Mix.Task

  @switches [ping: :boolean]

  def run(args) do
    DevTasksHelper.ensure_executable!("redis-cli")

    {_opts, _rest, _invalid} = OptionParser.parse(args, switches: @switches)

    host = DevTasksHelper.env("REDIS_HOSTNAME", "localhost")
    port = DevTasksHelper.env("REDIS_PORT", "6379")
    pass = System.get_env("REDIS_PASSWORD")

    base_args = ["-h", host, "-p", port]
    base_args = if pass in [nil, ""], do: base_args, else: base_args ++ ["-a", pass]

    cmd = if pass in [nil, ""], do: "redis-cli -h #{host} -p #{port}", else: ~s(redis-cli -h #{host} -p #{port} -a "#{pass}")
    IO.puts("Interactive redis-cli command:\n  #{cmd}")

    # Quick connectivity test
    DevTasksHelper.run_cmd!("redis-cli", base_args ++ ["PING"]) 
  end
end

