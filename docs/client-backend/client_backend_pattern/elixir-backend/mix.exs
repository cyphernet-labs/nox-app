defmodule Backend.MixProject do
  use Mix.Project

  def project do
    [
      app: :backend,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Backend.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      # Bandit: pure-Elixir HTTP server (endpoint adapter).
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      # exqlite: SQLite3 NIF. Used directly (no Ecto) so the SQL on the
      # page is the SQL executed. NOTE: a NIF is native C inside the VM —
      # a crash there takes down the whole node (see README).
      {:exqlite, "~> 0.27"}
    ]
  end
end
