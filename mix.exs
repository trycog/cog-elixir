defmodule CogElixir.MixProject do
  use Mix.Project

  @extension_metadata_path Path.expand("cog-extension.json", __DIR__)
  @version @extension_metadata_path
           |> File.read!()
           |> :json.decode()
           |> Map.fetch!("version")

  def project do
    [
      app: :cog_elixir,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: false,
      deps: deps(),
      escript: escript(),
      test_paths: ["test"],
      test_pattern: "*_test.exs"
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_html, "~> 4.2"}
    ]
  end

  defp escript do
    [main_module: CogElixir]
  end
end
