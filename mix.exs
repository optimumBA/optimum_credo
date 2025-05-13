defmodule OptimumCredo.MixProject do
  use Mix.Project

  @repo "https://github.com/optimumBA/optimum_credo"
  @version "0.1.0"

  @spec project() :: keyword()
  def project do
    [
      app: :optimum_credo,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex package
      description: "Optimum's Credo checks",
      package: package(),

      # Docs
      name: "OptimumCredo",
      source_url: @repo,
      docs: [
        extras: ["README.md"],
        main: "readme",
        source_ref: "v#{@version}"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  @spec application() :: keyword()
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @repo},
      maintainers: ["Almir Sarajčić"]
    ]
  end
end
