defmodule Mix.Tasks.Dev.Psql do
  @shortdoc "Print psql command or run a query"
  @moduledoc """
  Usage:
    mix dev.psql                 # prints interactive psql command and tests connectivity
    mix dev.psql --query SQL     # runs a one-off SQL query
  """
  use Mix.Task

  @switches [query: :string]

  def run(args) do
    DevTasksHelper.ensure_executable!("psql")

    {opts, _rest, _invalid} = OptionParser.parse(args, switches: @switches)

    user = DevTasksHelper.env("DB_USERNAME", "postgres")
    pass = DevTasksHelper.env("DB_PASSWORD", "postgres")
    host = DevTasksHelper.env("DB_HOSTNAME", "localhost")
    db   = DevTasksHelper.env("DB_DATABASE", "lang_dev")
    port = DevTasksHelper.env("DB_PORT", "5432")

    base_args = ["-h", host, "-p", port, "-U", user, "-d", db]

    case opts do
      [query: sql] when is_binary(sql) ->
        DevTasksHelper.run_cmd!(
          "psql",
          base_args ++ ["-c", sql],
          env: [{"PGPASSWORD", pass}],
          into: IO.stream(:stdio, :line)
        )

      _ ->
        cmd = ~s(PGPASSWORD=#{pass} psql -h #{host} -p #{port} -U #{user} -d #{db})
        IO.puts("Interactive psql command:\n  #{cmd}")
        # Quick connectivity test
        DevTasksHelper.run_cmd!(
          "psql",
          base_args ++ ["-c", "select 1"],
          env: [{"PGPASSWORD", pass}],
          into: IO.stream(:stdio, :line)
        )
    end
  end
end

