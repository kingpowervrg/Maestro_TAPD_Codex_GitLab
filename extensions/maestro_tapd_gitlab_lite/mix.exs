defmodule MaestroTapdGitlabLite.MixProject do
  use Mix.Project

  def project do
    [
      app: :maestro_tapd_gitlab_lite,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_options: [no_warn_undefined: :all],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {MaestroTapdGitlabLite.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:maestro_core_contracts, path: "../maestro_core_contracts", runtime: true},
      {:req, "~> 0.5"}
    ]
  end
end
