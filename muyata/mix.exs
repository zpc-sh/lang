defmodule Muyata.MixProject do
  use Mix.Project

  def project do
    [
      app: :muyata,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # AtomVM packbeam target
      atomvm: [
        start: Muyata.Application,
        flash_offset: 0x210000
      ]
    ]
  end

  def application do
    app = [extra_applications: [:logger, :crypto]]

    # Don't auto-start the full supervisor in test mode —
    # tests start_supervised! individual GenServers
    if Mix.env() == :test do
      app
    else
      Keyword.put(app, :mod, {Muyata.Application, []})
    end
  end

  # Zero deps. Pure Elixir/OTP stdlib only.
  # The void needs nothing to begin.
  defp deps do
    [
      # ExAtomVM: Mix task suite including atomvm.packbeam (dev/build only)
      {:exatomvm, git: "https://github.com/atomvm/ExAtomVM/", only: [:dev]},
      {:atomvm_packbeam, "~> 0.7", runtime: false, only: :dev}
    ]
  end
end
