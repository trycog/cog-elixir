defmodule CogElixir.Frontend do
  @moduledoc false

  alias CogElixir.Frontend.{EExFile, ElixirFile, HEExFile}

  def analyze(source, package_name, relative_path) do
    case classify_path(relative_path) do
      :heex -> HEExFile.analyze(source, package_name, relative_path)
      :eex -> EExFile.analyze(source, package_name, relative_path)
      :elixir -> ElixirFile.analyze(source, package_name, relative_path)
    end
  end

  def classify_path(path) do
    cond do
      String.ends_with?(path, ".html.heex") -> :heex
      String.ends_with?(path, ".heex") -> :heex
      String.ends_with?(path, ".html.eex") -> :eex
      String.ends_with?(path, ".eex") -> :eex
      true -> :elixir
    end
  end
end
