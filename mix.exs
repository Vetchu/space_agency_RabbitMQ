defmodule SpaceAgenciesRabbitmq.MixProject do
  use Mix.Project

  def project do
    [
      app: :Agency,
      version: "0.1.0",
      elixir: "~> 1.1",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [applications: [:amqp, :uuid]]
  end

  defp deps do
    [
      {:amqp, "~> 1.1"},
      {:uuid, "~> 1.1.8"}
    ]
  end
end
