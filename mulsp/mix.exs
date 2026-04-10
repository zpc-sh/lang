defmodule Mulsp.MixProject do
  use Mix.Project

  def project do
    [
      app: :mulsp,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # AtomVM packbeam target
      atomvm: [
        start: Mulsp.Application,
        flash_offset: 0x210000
      ]
    ]
  end

  def application do
    [
      mod: {Mulsp.Application, []},
      extra_applications: [:logger]
    ]
  end

  # No JSON. No fluff. Pure Erlang/Elixir stdlib only.
  # merkin.wasm loaded from priv/ via port or Popcorn bridge.
  defp deps do
    [
      # ExAtomVM: flashing + device tools (dev/build only)
      {:exatomvm, git: "https://github.com/atomvm/ExAtomVM/", only: [:dev]},
      # atomvm_packbeam: emits .avm packbeam from mix (dev/build only)
      {:atomvm_packbeam, "~> 0.7", runtime: false, only: :dev}
      # Burrito for single-binary fallback
      # {:burrito, github: "burrito-elixir/burrito", only: :prod}
    ]
  end
end
