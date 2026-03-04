defmodule CogElixir.Workspace do
  @moduledoc false

  def find_root(path) do
    abs_path = Path.expand(path)

    dir =
      if File.dir?(abs_path) do
        abs_path
      else
        Path.dirname(abs_path)
      end

    walk_up(dir)
  end

  defp walk_up(dir) do
    mix_path = Path.join(dir, "mix.exs")

    cond do
      File.exists?(mix_path) ->
        dir

      dir == "/" ->
        dir

      true ->
        parent = Path.dirname(dir)

        if parent == dir do
          dir
        else
          walk_up(parent)
        end
    end
  end

  def discover_project_name(workspace_root) do
    mix_path = Path.join(workspace_root, "mix.exs")

    case File.read(mix_path) do
      {:ok, content} ->
        case Regex.run(~r/app:\s*:(\w+)/, content) do
          [_, name] -> name
          _ -> Path.basename(workspace_root)
        end

      {:error, _} ->
        Path.basename(workspace_root)
    end
  end
end
