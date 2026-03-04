defmodule CogElixir do
  @moduledoc false

  alias CogElixir.{CLI, Workspace, Analyzer, Protobuf, Scip}

  @version "0.1.0"

  def main(args) do
    case CLI.parse(args) do
      {:ok, input_path, output_path} ->
        run(input_path, output_path)

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  defp run(input_path, output_path) do
    abs_input = Path.expand(input_path)

    unless File.exists?(abs_input) do
      IO.puts(:stderr, "Error: file not found: #{abs_input}")
      System.halt(1)
    end

    workspace_root = Workspace.find_root(abs_input)
    project_name = Workspace.discover_project_name(workspace_root)
    relative_path = Path.relative_to(abs_input, workspace_root)

    source = File.read!(abs_input)

    document = Analyzer.analyze(source, project_name, relative_path)

    index = %Scip.Index{
      metadata: %Scip.Metadata{
        version: 0,
        tool_info: %Scip.ToolInfo{
          name: "cog-elixir",
          version: @version,
          arguments: args_list()
        },
        project_root: "file://#{workspace_root}",
        text_document_encoding: 1
      },
      documents: [document],
      external_symbols: []
    }

    data = Protobuf.encode_index(index)
    File.write!(output_path, data)
  end

  defp args_list do
    System.argv()
  end
end
