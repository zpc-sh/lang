defmodule AshProfiler.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nocsi/ash_profiler"

  def project do
    [
      app: :ash_profiler,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "AshProfiler",
      aliases: aliases(),
      preferred_cli_env: [
        "test.watch": :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp description do
    """
    Performance profiling and optimization toolkit for Ash Framework applications.
    Analyze DSL complexity, identify compilation bottlenecks, and get actionable optimization recommendations.
    """
  end

  defp package do
    [
      name: "ash_profiler",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG* AGENTS*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Ash Framework" => "https://ash-hq.org"
      },
      maintainers: ["nocsi"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "AGENTS.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        "Getting Started": ["README.md"],
        "Community": ["AGENTS.md"],
        "Legal": ["LICENSE", "CHANGELOG.md"]
      ],
      groups_for_modules: [
        "Core": [AshProfiler],
        "Analysis": [
          AshProfiler.DomainAnalyzer,
          AshProfiler.DSLProfiler
        ],
        "Container Support": [
          AshProfiler.ContainerDetector,
          AshProfiler.ContainerProfiler,
          AshProfiler.DockerOptimizer
        ],
        "Mix Tasks": [
          Mix.Tasks.AshProfiler,
          Mix.Tasks.AshProfiler.Docker,
          Mix.Tasks.DebugCompilation
        ]
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "compile"],
      test: ["test --trace"],
      "test.watch": ["test.watch --trace"],
      "ash_profiler.demo": ["ash_profiler --output html --file demo_report.html"]
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:ash, "~> 3.0"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},
      
      # Development dependencies
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
