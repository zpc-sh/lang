defmodule JsonldEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :jsonld_ex,
      version: "0.4.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      # BUILD: Documentation and dialyzer
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.34.0", runtime: false},
      {:rustler_precompiled, "~> 0.8"},
      {:jason, "~> 1.2"},
      {:json_ld, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end


  # BUILD: Documentation configuration
  defp docs do
    [
      main: "JsonldEx",
      name: "JsonldEx",
      source_url: "https://github.com/nocsi/jsonld",
      homepage_url: "https://github.com/nocsi/jsonld",
      extras: ["README.md"]
    ]
  end

  # BUILD: Dialyzer configuration for static analysis
  defp dialyzer do
    [
      plt_add_deps: :app_tree,
      plt_add_apps: [:ex_unit],
      flags: [:unmatched_returns, :error_handling, :race_conditions]
    ]
  end

  defp package() do
    [
      name: "jsonld_ex",
      licenses: ["Apache-2.0"],
      maintainers: ["NOCSI"],
      description:
        "A JSON-LD library for Elixir, providing a Rust-based implementation for performance.",
      files:
        ~w(lib priv mix.exs README.md LICENSE) ++
          [
            "native/jsonld_nif/src",
            "native/jsonld_nif/Cargo.toml",
            "native/jsonld_nif/Cargo.lock",
            "native/jsonld_nif/README.md",
            "native/jsonld_nif/.gitignore",
            "native/jsonld_nif/.cargo"
          ],
      links: %{"GitHub" => "https://github.com/nocsi/jsonld"}
    ]
  end
end
