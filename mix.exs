defmodule Extreme.System.Mixfile do
  use Mix.Project

  def project do
    [app: :extreme_system,
     version: "0.0.1",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [
      applications: [
        :logger, :extreme
      ]
    ]
  end

  defp deps do
    [
      {:extreme, "~> 0.7.1 or ~> 0.8.0"},
    ]
  end
end
