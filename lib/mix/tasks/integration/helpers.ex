defmodule Mix.Tasks.Integration.Helpers do
  @moduledoc false

  # Colors
  @green "\e[0;32m"
  @red "\e[0;31m"
  @yellow "\e[0;33m"
  @cyan "\e[0;36m"
  @reset "\e[0m"

  def start_counters do
    Agent.start_link(fn -> %{pass: 0, fail: 0, warn: 0, skip: 0} end, name: __MODULE__)
  end

  def pass(msg) do
    Agent.update(__MODULE__, &Map.update!(&1, :pass, fn n -> n + 1 end))
    IO.puts("  #{@green}PASS#{@reset} #{msg}")
  end

  def fail(msg) do
    Agent.update(__MODULE__, &Map.update!(&1, :fail, fn n -> n + 1 end))
    IO.puts("  #{@red}FAIL#{@reset} #{msg}")
  end

  def warn(msg) do
    Agent.update(__MODULE__, &Map.update!(&1, :warn, fn n -> n + 1 end))
    IO.puts("  #{@yellow}WARN#{@reset} #{msg}")
  end

  def skip(msg) do
    Agent.update(__MODULE__, &Map.update!(&1, :skip, fn n -> n + 1 end))
    IO.puts("  #{@cyan}SKIP#{@reset} #{msg}")
  end

  def check_prerequisites(commands) do
    missing =
      Enum.filter(commands, fn cmd ->
        System.find_executable(cmd) == nil
      end)

    case missing do
      [] -> :ok
      list -> {:missing, list}
    end
  end

  def with_fixture(fixture_name, callback) do
    tmpdir = System.tmp_dir!()
    work_dir = Path.join(tmpdir, "cog-elixir-#{fixture_name}-#{:rand.uniform(999_999)}")
    fixture_src = Path.join([File.cwd!(), "integration_tests", "fixtures", "debug_app"])

    project_root = File.cwd!()

    File.mkdir_p!(work_dir)

    # Copy fixture contents
    {_, 0} = System.cmd("cp", ["-r", fixture_src <> "/.", work_dir])

    # Copy project .mcp.json and .claude/settings* so claude can find MCP servers
    # but NOT .claude/agents/ to prevent subagent delegation
    mcp_json = Path.join(project_root, ".mcp.json")
    claude_dir = Path.join(project_root, ".claude")

    if File.exists?(mcp_json), do: File.cp!(mcp_json, Path.join(work_dir, ".mcp.json"))

    if File.dir?(claude_dir) do
      dest_claude = Path.join(work_dir, ".claude")
      File.mkdir_p!(dest_claude)

      # Copy settings files only, skip agents/
      for file <- File.ls!(claude_dir),
          Path.extname(file) in [".json", ".local.json"] or
            file in ["settings.json", "settings.local.json"] do
        src = Path.join(claude_dir, file)
        if File.regular?(src), do: File.cp!(src, Path.join(dest_claude, file))
      end
    end

    IO.puts("Working directory: #{work_dir}")

    try do
      callback.(work_dir)
    after
      File.rm_rf!(work_dir)
    end
  end

  def cmd(command, args, opts \\ []) do
    timeout_secs = Keyword.get(opts, :timeout, 120_000) |> div(1000)
    cd = Keyword.get(opts, :cd, nil)

    # Build base env: unset CLAUDECODE to allow nested claude -p invocations
    env = [{"CLAUDECODE", nil}]
    env = env ++ Keyword.get(opts, :env, [])

    cmd_opts = [stderr_to_stdout: true, env: env]
    cmd_opts = if cd, do: Keyword.put(cmd_opts, :cd, cd), else: cmd_opts

    # Build a shell command string with proper escaping.
    # We use sh -c with </dev/null to close stdin — without this,
    # System.cmd keeps stdin open as a pipe and claude -p hangs
    # waiting for input it will never receive.
    shell_cmd =
      [command | args]
      |> Enum.map(&shell_escape/1)
      |> Enum.join(" ")

    {output, exit_code} =
      System.cmd("sh", ["-c", "timeout #{timeout_secs} #{shell_cmd} </dev/null"], cmd_opts)

    {exit_code, output}
  end

  def print_summary do
    counts = Agent.get(__MODULE__, & &1)

    IO.puts("")

    IO.puts(
      "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"
    )

    IO.puts("  #{@green}Passed:  #{counts.pass}#{@reset}")
    IO.puts("  #{@red}Failed:  #{counts.fail}#{@reset}")
    IO.puts("  #{@yellow}Warnings: #{counts.warn}#{@reset}")
    IO.puts("  #{@cyan}Skipped: #{counts.skip}#{@reset}")

    IO.puts(
      "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"
    )

    if counts.fail > 0 do
      IO.puts("#{@red}SUITE FAILED#{@reset}")
      :error
    else
      IO.puts("#{@green}SUITE PASSED#{@reset}")
      :ok
    end
  end

  def assert_exit_code(actual, expected, msg) do
    if actual == expected do
      pass(msg)
    else
      fail("#{msg} (expected exit #{expected}, got #{actual})")
    end
  end

  def assert_file_exists(path, msg) do
    if File.exists?(path) do
      pass(msg)
    else
      fail("#{msg} (file not found: #{path})")
    end
  end

  def assert_file_not_empty(path, msg) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > 0 -> pass(msg)
      _ -> fail("#{msg} (file empty or missing: #{path})")
    end
  end

  def assert_output_contains(output, pattern, msg) do
    if String.contains?(output, pattern) do
      pass(msg)
    else
      fail("#{msg} (pattern '#{pattern}' not found in output)")
    end
  end

  defp shell_escape(arg) do
    "'" <> String.replace(arg, "'", "'\\''") <> "'"
  end
end
