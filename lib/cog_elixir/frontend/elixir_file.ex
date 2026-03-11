defmodule CogElixir.Frontend.ElixirFile do
  @moduledoc false

  alias CogElixir.Analyzer

  def analyze(source, package_name, relative_path) do
    Analyzer.analyze(source, package_name, relative_path)
  end
end
