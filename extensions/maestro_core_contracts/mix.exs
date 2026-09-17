defmodule MaestroCoreContracts.MixProject do
  use Mix.Project

  def project do
    [
      app: :maestro_core_contracts,
      version: "1.0.0",
      elixir: "~> 1.19",
      elixirc_options: [no_warn_undefined: :all],
      deps: []
    ]
  end

  def application, do: []
end
