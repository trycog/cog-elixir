defmodule CogElixir do
  @moduledoc false

  alias CogElixir.{CLI, Workspace, Frontend, Protobuf, Scip}

  @version "0.1.0"
  @watchdog_interval_ms 5_000

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
    timeout = file_timeout()

    file_paths
    |> Task.async_stream(&analyze_file/1,
      max_concurrency: System.schedulers_online(),
      ordered: false,
      timeout: timeout,
      on_timeout: :kill_task
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
    file_size = file_size(abs_input)

    debug_log("file_start",
      path: relative_path,
      abs_path: abs_input,
      size_bytes: file_size,
      memory: memory_snapshot(),
      timeout_ms: file_timeout_value()
    )

    watchdog = start_watchdog(relative_path, abs_input, file_size)

    cond do
      not File.exists?(abs_input) ->
        warn("skipping missing file: #{abs_input}")
        result = build_result(workspace_root, project_name, empty_document(relative_path), :error)
        stop_watchdog(watchdog, relative_path, :error)
        result

      true ->
        try do
          source = timed_stage(relative_path, "read_file", fn -> File.read!(abs_input) end)

          document =
            timed_stage(relative_path, "analyze", fn ->
              Frontend.analyze(source, project_name, relative_path)
            end)

          result = build_result(workspace_root, project_name, document, :ok)
          stop_watchdog(watchdog, relative_path, :ok)
          result
        rescue
          error ->
            warn("failed to index #{relative_path}: #{Exception.message(error)}")

            debug_log("file_exception",
              path: relative_path,
              kind: "error",
              message: Exception.message(error),
              memory: memory_snapshot()
            )

            result =
              build_result(workspace_root, project_name, empty_document(relative_path), :error)

            stop_watchdog(watchdog, relative_path, :error)
            result
        catch
          kind, reason ->
            warn("failed to index #{relative_path}: #{kind} #{inspect(reason)}")

            debug_log("file_exception",
              path: relative_path,
              kind: inspect(kind),
              message: inspect(reason),
              memory: memory_snapshot()
            )

            result =
              build_result(workspace_root, project_name, empty_document(relative_path), :error)

            stop_watchdog(watchdog, relative_path, :error)
            result
        end
    end
  end

  defp timed_stage(path, stage, fun) do
    started_at = System.monotonic_time(:millisecond)

    debug_log("stage_start",
      path: path,
      stage: stage,
      memory: memory_snapshot()
    )

    result = fun.()
    duration_ms = System.monotonic_time(:millisecond) - started_at

    debug_log("stage_finish",
      path: path,
      stage: stage,
      duration_ms: duration_ms,
      memory: memory_snapshot()
    )

    result
  end

  defp start_watchdog(relative_path, abs_input, file_size) do
    if debug_enabled?() do
      parent = self()

      spawn_link(fn ->
        ref = Process.monitor(parent)

        watchdog_loop(
          parent,
          ref,
          relative_path,
          abs_input,
          file_size,
          System.monotonic_time(:millisecond)
        )
      end)
    else
      nil
    end
  end

  defp watchdog_loop(parent, ref, relative_path, abs_input, file_size, started_at) do
    receive do
      {:stop_watchdog, ^parent, status} ->
        debug_log("file_finish",
          path: relative_path,
          abs_path: abs_input,
          status: status,
          size_bytes: file_size,
          duration_ms: System.monotonic_time(:millisecond) - started_at,
          memory: memory_snapshot(parent)
        )

      {:DOWN, ^ref, :process, ^parent, reason} ->
        debug_log("watchdog_down",
          path: relative_path,
          reason: inspect(reason),
          duration_ms: System.monotonic_time(:millisecond) - started_at,
          memory: memory_snapshot()
        )
    after
      @watchdog_interval_ms ->
        debug_log("file_still_running",
          path: relative_path,
          abs_path: abs_input,
          size_bytes: file_size,
          duration_ms: System.monotonic_time(:millisecond) - started_at,
          task_memory: process_memory(parent),
          task_reductions: process_reductions(parent),
          task_queue_len: process_message_queue_len(parent),
          memory: memory_snapshot(parent)
        )

        watchdog_loop(parent, ref, relative_path, abs_input, file_size, started_at)
    end
  end

  defp stop_watchdog(nil, _relative_path, _status), do: :ok

  defp stop_watchdog(pid, _relative_path, status) do
    send(pid, {:stop_watchdog, self(), status})
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

  defp debug_enabled? do
    System.get_env("COG_ELIXIR_DEBUG") in ["1", "true", "TRUE", "yes", "YES"]
  end

  defp file_timeout do
    case file_timeout_value() do
      :infinity -> :infinity
      timeout -> timeout
    end
  end

  defp file_timeout_value do
    case System.get_env("COG_ELIXIR_FILE_TIMEOUT_MS") do
      nil ->
        :infinity

      value ->
        case Integer.parse(value) do
          {timeout, _} when timeout > 0 -> timeout
          _ -> :infinity
        end
    end
  end

  defp debug_log(event, attrs) do
    if debug_enabled?() do
      payload =
        attrs
        |> Enum.into(%{})
        |> Map.put(:type, "debug")
        |> Map.put(:event, event)
        |> JasonFallback.encode()

      IO.puts(:stderr, payload)
    end
  end

  defp memory_snapshot(pid \\ self()) do
    %{
      system_total: :erlang.memory(:total),
      system_processes: :erlang.memory(:processes),
      system_binary: :erlang.memory(:binary),
      process_memory: process_memory(pid),
      process_heap_size: process_info_value(pid, :heap_size),
      process_total_heap_size: process_info_value(pid, :total_heap_size),
      process_stack_size: process_info_value(pid, :stack_size),
      process_reductions: process_reductions(pid),
      process_gc: process_info_value(pid, :garbage_collection)
    }
  end

  defp process_memory(pid), do: process_info_value(pid, :memory)
  defp process_reductions(pid), do: process_info_value(pid, :reductions)
  defp process_message_queue_len(pid), do: process_info_value(pid, :message_queue_len)

  defp process_info_value(pid, key) do
    case Process.info(pid, key) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.size
      _ -> nil
    end
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

defmodule JasonFallback do
  @moduledoc false

  def encode(map) when is_map(map) do
    entries =
      map
      |> Enum.map(fn {key, value} ->
        "\"#{escape(to_string(key))}\":#{encode_value(value)}"
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp encode_value(value) when is_binary(value), do: "\"#{escape(value)}\""
  defp encode_value(value) when is_integer(value), do: Integer.to_string(value)
  defp encode_value(value) when is_float(value), do: :erlang.float_to_binary(value, [:compact])
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"
  defp encode_value(nil), do: "null"
  defp encode_value(value) when is_map(value), do: encode(value)

  defp encode_value(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &encode_value/1) <> "]"

  defp encode_value(value), do: "\"#{escape(inspect(value))}\""

  defp escape(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
end
