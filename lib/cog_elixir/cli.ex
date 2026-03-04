defmodule CogElixir.CLI do
  @moduledoc false

  def parse(args) do
    case parse_args(args, nil, nil) do
      {file_path, output_path} when is_binary(file_path) and is_binary(output_path) ->
        {:ok, file_path, output_path}

      _ ->
        {:error, "Usage: cog-elixir <file_path> --output <output_path>"}
    end
  end

  defp parse_args([], file_path, output_path), do: {file_path, output_path}

  defp parse_args(["--output", output_path | rest], file_path, _) do
    parse_args(rest, file_path, output_path)
  end

  defp parse_args([file_path | rest], nil, output_path) do
    parse_args(rest, file_path, output_path)
  end

  defp parse_args([_ | rest], file_path, output_path) do
    parse_args(rest, file_path, output_path)
  end
end
