defmodule CogElixir.CLI do
  @moduledoc false

  def parse(args) do
    case parse_args(args, [], nil) do
      {file_paths, output_path}
      when is_list(file_paths) and is_binary(output_path) and file_paths != [] ->
        {:ok, Enum.reverse(file_paths), output_path}

      _ ->
        {:error, "Usage: cog-elixir --output <output_path> <file_path> [file_path ...]"}
    end
  end

  defp parse_args([], file_paths, output_path), do: {file_paths, output_path}

  defp parse_args(["--output", output_path | rest], file_paths, _) do
    parse_args(rest, file_paths, output_path)
  end

  defp parse_args([file_path | rest], file_paths, output_path) do
    parse_args(rest, [file_path | file_paths], output_path)
  end
end
