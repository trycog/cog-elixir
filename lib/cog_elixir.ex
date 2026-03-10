defmodule CogElixir do
  @moduledoc false

  alias CogElixir.{CLI, Workspace, Analyzer, Protobuf, Scip}

  @version "0.1.0"

  def main(args) do
    case CLI.parse(args) do
      {:ok, file_paths, output_path} ->
        run(file_paths, output_path)

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  defp run(file_paths, output_path) do
    results = analyze_files(file_paths)
    documents = Enum.map(results, & &1.document)
    workspace_root = infer_workspace_root(results)

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
      documents: documents,
      external_symbols: []
    }

    data = Protobuf.encode_index(index)
    File.write!(output_path, data)
  end

  defp analyze_files(file_paths) do
    file_paths
    |> Task.async_stream(&analyze_file/1,
      max_concurrency: System.schedulers_online(),
      ordered: false,
      timeout: :infinity
    )
    |> Enum.map(fn
      {:ok, result} ->
        emit_progress(result.status, result.document.relative_path)
        result

      {:exit, reason} ->
        warn("task crashed while indexing file batch entry: #{Exception.format_exit(reason)}")
        emit_progress(:error, "")

        default_root = default_project_root()

        %{
          workspace_root: default_root,
          project_name: Workspace.discover_project_name(default_root),
          document: %Scip.Document{language: "elixir", relative_path: ""},
          status: :error
        }
    end)
  end

  defp analyze_file(file_path) do
    abs_input = Path.expand(file_path)
    workspace_root = Workspace.find_root(abs_input)
    project_name = Workspace.discover_project_name(workspace_root)
    relative_path = Path.relative_to(abs_input, workspace_root)

    cond do
      not File.exists?(abs_input) ->
        warn("skipping missing file: #{abs_input}")
        build_result(workspace_root, project_name, empty_document(relative_path), :error)

      true ->
        try do
          source = File.read!(abs_input)
          document = Analyzer.analyze(source, project_name, relative_path)
          build_result(workspace_root, project_name, document, :ok)
        rescue
          error ->
            warn("failed to index #{relative_path}: #{Exception.message(error)}")
            build_result(workspace_root, project_name, empty_document(relative_path), :error)
        catch
          kind, reason ->
            warn("failed to index #{relative_path}: #{kind} #{inspect(reason)}")
            build_result(workspace_root, project_name, empty_document(relative_path), :error)
        end
    end
  end

  defp build_result(workspace_root, project_name, document, status) do
    %{
      workspace_root: workspace_root,
      project_name: project_name,
      document: document,
      status: status
    }
  end

  defp empty_document(relative_path) do
    %Scip.Document{language: "elixir", relative_path: relative_path}
  end

  defp infer_workspace_root([first | _results]), do: first.workspace_root
  defp infer_workspace_root([]), do: default_project_root()

  defp default_project_root, do: File.cwd!()

  defp warn(message) do
    IO.puts(:stderr, "Warning: #{message}")
  end

  defp emit_progress(status, path) do
    event = if status == :ok, do: "file_done", else: "file_error"
    IO.puts(:stderr, ~s|{"type":"progress","event":"#{event}","path":"#{escape_json(path)}"}|)
  end

  defp escape_json(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp args_list do
    System.argv()
  end
end
