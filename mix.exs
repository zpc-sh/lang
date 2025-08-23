defmodule Lang.MixProject do
  use Mix.Project

  def project do
    [
      app: :lang,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      rustler_crates: rustler_crates()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Lang.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:igniter, "~> 0.6", only: [:dev, :test]},
      # Phoenix & Web
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},

      # Ash Framework
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.0"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_json_api, "~> 1.0"},
      {:ash_authentication, "~> 4.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:ash_oban, "~> 0.2"},
      {:open_api_spex, "~> 3.16"},
      # For cloud orchestration
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      # For distributed orchestration
      {:libcluster, "~> 3.3"},

      # Native Performance Engines
      {:rustler, "~> 0.34.0", optional: true},
      {:rustler_precompiled, "~> 0.7"},

      # Utilities
      {:number, "~> 1.0"},

      # Background Processing & Caching
      {:oban, "~> 2.15"},
      {:cachex, "~> 3.6"},
      {:redix, "~> 1.2"},

      # Text Processing & Analysis
      {:unicode, "~> 1.18"},
      {:yaml_elixir, "~> 2.9"},
      {:nimble_parsec, "~> 1.0"},
      {:makeup, "~> 1.1"},
      {:makeup_elixir, "~> 0.16"},

      # HTTP & API
      {:req, "~> 0.5"},
      {:finch, "~> 0.13"},
      {:mint, "~> 1.0"},

      # Payment Processing
      {:stripity_stripe, "~> 3.0"},
      {:money, "~> 1.12"},

      # Development & Testing
      {:floki, ">= 0.30.0", only: :test},
      {:ex_machina, "~> 2.7", only: :test},
      {:faker, "~> 0.17", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:sobelow, "~> 0.8", only: [:dev, :test], runtime: false},
      {:bcrypt_elixir, "~> 3.0"},
      {:tidewave, "~> 0.4", only: [:dev, :test]},
      {:jsonld_ex, "~> 0.1.1"},
      {:markdown_ld, "~> 0.3"},

      # Performance profiling and optimization
      {:ash_profiler, "~> 0.1.0", only: [:dev, :test]}
    ]
  end

  # Rustler configuration for native NIFs
  defp rustler_crates do
    [
      lang_parser: [
        path: "native/lang_parser",
        mode: rustler_mode(Mix.env())
      ],
      lang_perf: [
        path: "native/lang_perf",
        mode: rustler_mode(Mix.env())
      ],
      fs_watcher: [
        path: "native/fs_watcher",
        mode: rustler_mode(Mix.env())
      ],
      tree_parser: [
        path: "native/tree_parser",
        mode: rustler_mode(Mix.env())
      ],
      fs_scanner: [
        path: "native/fs_scanner",
        mode: rustler_mode(Mix.env())
      ]
    ]
  end

  defp rustler_mode(:prod), do: :release
  defp rustler_mode(_), do: :debug

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind lang", "esbuild lang"],
      "assets.deploy": [
        "tailwind lang --minify",
        "esbuild lang --minify",
        "phx.digest"
      ],

      # Development and maintenance
      precommit: ["precommit"],
      clean: ["clean.artifacts --force"],
      "dev.reset": ["dev.clean --all --deps --force"],
      "dev.quick": ["dev.clean --artifacts --format --force"],

      # Native compilation
      "compile.native": ["rustler.compile"],
      "clean.native": ["rustler.clean"],
      "bench.native": ["compile.native", "run -e 'Lang.Native.Benchmarks.run_all()'"]
    ]
  end
end
