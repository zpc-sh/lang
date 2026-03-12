defmodule MarkdownLd.MixProject do
  use Mix.Project

  def project do
    [
      app: :markdown_ld,
      version: "0.4.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      
      # BUILD: Documentation and dialyzer  
      docs: docs(),
      dialyzer: dialyzer(),
      description: description(),
      source_url: "https://github.com/nocsi/markdown-ld"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MarkdownLd.Application, []}
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.34.0", runtime: false},
      {:rustler_precompiled, "~> 0.8"},
      {:jason, "~> 1.2"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "High-performance Markdown processing library with SIMD optimizations, JSON-LD integration, and parallel batch processing."
  end

  # BUILD: Documentation configuration
  defp docs do
    [
      main: "MarkdownLd",
      name: "MarkdownLd",
      source_url: "https://github.com/nocsi/markdown-ld",
      homepage_url: "https://github.com/nocsi/markdown-ld",
      extras: [
        "README.md",
        "SPEC.md": [title: "Markdown‑LD Profile"],
        "PERFORMANCE_REPORT.md": [title: "Performance Report"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_modules: [
        "Core API": [MarkdownLd],
        "Native Interface": [MarkdownLd.Native],
        "Application": [MarkdownLd.Application]
      ],
      groups_for_extras: [
        "Introduction": ~r/README/,
        "Performance": ~r/PERFORMANCE/,
        "Release Notes": ~r/CHANGELOG/
      ],
      api_reference: false,
      formatters: ["html", "epub"],
      authors: ["NOCSI"],
      source_ref: "v0.4.0",
      canonical: "http://hexdocs.pm/markdown_ld",
      language: "en"
    ]
  end

  # BUILD: Dialyzer configuration for static analysis
  defp dialyzer do
    [
      plt_add_deps: :app_tree,
      plt_add_apps: [:ex_unit],
      flags: [:unmatched_returns, :error_handling, :race_conditions, :underspecs]
    ]
  end

  # BUILD: Hex.pm package configuration
  defp package do
    [
      name: "markdown_ld",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE SPEC.md 
                CHANGELOG.md native/markdown_ld_nif/src 
                native/markdown_ld_nif/Cargo.toml native/markdown_ld_nif/Cargo.lock
                native/markdown_ld_nif/.cargo),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/nocsi/markdown-ld"},
      maintainers: ["NOCSI"],
      exclude_patterns: [
        "native/*/target",
        "native/*/.git*"
      ]
    ]
  end
end
