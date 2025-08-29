ExUnit.start()

skip_db = String.downcase(System.get_env("SKIP_DB") || "0") in ["1", "true", "yes", "on"]
unless skip_db do
  Ecto.Adapters.SQL.Sandbox.mode(Lang.Repo, :manual)
end
