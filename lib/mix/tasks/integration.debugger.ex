defmodule Mix.Tasks.Integration.Debugger do
  @moduledoc "Integration tests for cog debugger via claude -p"
  @shortdoc "Run debugger integration tests"
  use Mix.Task

  alias Mix.Tasks.Integration.Helpers

  @skip_tests [
    "Full debug session via claude -p",
    "Struct inspection debug session"
  ]

  @debug_tools "mcp__cog__cog_debug_launch,mcp__cog__cog_debug_breakpoint,mcp__cog__cog_debug_run,mcp__cog__cog_debug_inspect,mcp__cog__cog_debug_stacktrace,mcp__cog__cog_debug_stop"
  @struct_tools "mcp__cog__cog_debug_launch,mcp__cog__cog_debug_breakpoint,mcp__cog__cog_debug_run,mcp__cog__cog_debug_inspect,mcp__cog__cog_debug_stop"

  @impl Mix.Task
  def run(_args) do
    Helpers.start_counters()

    IO.puts("")
    IO.puts("=== Debugger Integration Tests ===")
    IO.puts("")

    missing =
      ["claude", "elixir_ls"]
      |> Enum.filter(fn cmd ->
        if System.find_executable(cmd) == nil do
          IO.puts("Skipping debugger tests: '#{cmd}' not found in PATH")
          true
        else
          false
        end
      end)

    if missing != [] do
      Enum.each(@skip_tests, &Helpers.skip/1)
      Helpers.print_summary()
    else
      run_tests()
    end
  end

  defp run_tests do
    Helpers.with_fixture("debugger", fn work_dir ->
      # Compile the project
      IO.puts("Compiling fixture project...")
      Helpers.cmd("mix", ["compile"], cd: work_dir)

      test_factorial_session(work_dir)
      test_struct_session(work_dir)

      Helpers.print_summary()
    end)
  end

  # Test 1: Full debug session via claude -p
  defp test_factorial_session(work_dir) do
    IO.puts("--- Test: Full debug session via claude -p ---")

    debug_prompt = """
    You are testing a debugger. Do NOT delegate to subagents. Use the MCP tools directly yourself. Follow these steps EXACTLY:

    1. Call cog_debug_launch with: program="mix", args=["run", "-e", "DebugApp.Math.factorial(5)"], language="elixir", cwd="#{work_dir}", stop_on_entry=false
    2. Call cog_debug_breakpoint with: session_id from step 1, action="set", file="#{work_dir}/lib/debug_app/math.ex", line=11
    3. Call cog_debug_run with: session_id, action="continue"
    4. Call cog_debug_inspect with: session_id, expression="n"
    5. Call cog_debug_stacktrace with: session_id
    6. Call cog_debug_stop with: session_id

    After completing all steps, output EXACTLY these markers (each on its own line) with your findings:
    BREAKPOINT_HIT: yes or no
    VARIABLE_N_VALUE: <the value of n when breakpoint was hit>
    STACKTRACE_DEPTH: <number of frames in the stacktrace>
    SESSION_COMPLETED: yes or no

    Do not output anything else after the markers.\
    """

    {exit_code, resp} =
      Helpers.cmd(
        "claude",
        ["-p", debug_prompt, "--allowedTools", @debug_tools],
        cd: work_dir,
        timeout: 180_000
      )

    IO.puts("  claude exit code: #{exit_code}")
    IO.puts("  claude response length: #{String.length(resp)}")
    IO.puts("  claude response:")
    IO.puts("  ---")
    IO.puts(resp)
    IO.puts("  ---")

    # Parse markers
    breakpoint_hit = parse_marker(resp, "BREAKPOINT_HIT")
    variable_n = parse_marker(resp, "VARIABLE_N_VALUE")
    stacktrace_depth = parse_marker(resp, "STACKTRACE_DEPTH")
    session_completed = parse_marker(resp, "SESSION_COMPLETED")

    evaluate_marker(breakpoint_hit, "yes", "Breakpoint was hit", "BREAKPOINT_HIT")
    evaluate_variable(variable_n, "Variable n inspected", "VARIABLE_N_VALUE")
    evaluate_stacktrace(stacktrace_depth)
    evaluate_marker(session_completed, "yes", "Debug session completed", "SESSION_COMPLETED")
  end

  # Test 2: Struct inspection debug session
  defp test_struct_session(work_dir) do
    IO.puts("--- Test: Struct inspection debug session ---")

    struct_prompt = """
    You are testing a debugger. Do NOT delegate to subagents. Use the MCP tools directly yourself. Follow these steps EXACTLY:

    1. Call cog_debug_launch with: program="mix", args=["run", "-e", "DebugApp.Runner.run()"], language="elixir", cwd="#{work_dir}", stop_on_entry=false
    2. Call cog_debug_breakpoint with: session_id from step 1, action="set", file="#{work_dir}/lib/debug_app/runner.ex", line=12
    3. Call cog_debug_run with: session_id, action="continue", timeout_ms=60000
    4. Call cog_debug_inspect with: session_id, expression="app"
    5. Call cog_debug_stop with: session_id

    After completing all steps, output EXACTLY these markers (each on its own line):
    STRUCT_BP_VERIFIED: <true or false, from the breakpoint response "verified" field>
    STRUCT_RUN_STOP_REASON: <the stop_reason from cog_debug_run response, e.g. breakpoint, timeout, exited, step>
    STRUCT_BREAKPOINT_HIT: yes or no (was stop_reason "breakpoint"?)
    STRUCT_HAS_NAME: yes or no (does the inspected app value contain a name field?)
    STRUCT_HAS_ITEMS: yes or no (does the inspected app value contain an items field?)
    STRUCT_SESSION_DONE: yes or no

    Do not output anything else after the markers.\
    """

    {exit_code, resp} =
      Helpers.cmd(
        "claude",
        ["-p", struct_prompt, "--allowedTools", @struct_tools],
        cd: work_dir,
        timeout: 180_000
      )

    IO.puts("  claude exit code: #{exit_code}")
    IO.puts("  claude response length: #{String.length(resp)}")
    IO.puts("  claude response:")
    IO.puts("  ---")
    IO.puts(resp)
    IO.puts("  ---")

    # Diagnostic markers
    bp_verified = parse_marker(resp, "STRUCT_BP_VERIFIED")
    run_stop = parse_marker(resp, "STRUCT_RUN_STOP_REASON")
    if bp_verified, do: IO.puts("  [diag] breakpoint verified: #{bp_verified}")
    if run_stop, do: IO.puts("  [diag] run stop_reason: #{run_stop}")

    struct_bp = parse_marker(resp, "STRUCT_BREAKPOINT_HIT")
    struct_name = parse_marker(resp, "STRUCT_HAS_NAME")
    struct_items = parse_marker(resp, "STRUCT_HAS_ITEMS")
    struct_done = parse_marker(resp, "STRUCT_SESSION_DONE")

    evaluate_marker(struct_bp, "yes", "Struct breakpoint was hit", "STRUCT_BREAKPOINT_HIT")
    evaluate_marker(struct_name, "yes", "Struct has name field", "STRUCT_HAS_NAME")
    evaluate_marker(struct_items, "yes", "Struct has items field", "STRUCT_HAS_ITEMS")
    evaluate_marker(struct_done, "yes", "Struct debug session completed", "STRUCT_SESSION_DONE")
  end

  # Marker parsing helpers

  defp parse_marker(output, marker) do
    case Regex.run(~r/#{Regex.escape(marker)}:\s*(\S+)/, output) do
      [_, value] -> value
      nil -> nil
    end
  end

  defp evaluate_marker(value, expected, pass_msg, marker_name) do
    cond do
      value == expected -> Helpers.pass(pass_msg)
      value != nil -> Helpers.warn("#{marker_name} marker: #{value}")
      true -> Helpers.warn("Could not parse #{marker_name} marker from response")
    end
  end

  defp evaluate_variable(value, pass_msg, marker_name) do
    cond do
      value != nil and value != "unknown" -> Helpers.pass("#{pass_msg} (value: #{value})")
      value != nil -> Helpers.warn("Variable n value: #{value}")
      true -> Helpers.warn("Could not parse #{marker_name} marker from response")
    end
  end

  defp evaluate_stacktrace(value) do
    cond do
      value != nil and value != "0" and value != "unknown" ->
        Helpers.pass("Stacktrace retrieved (depth: #{value})")

      value != nil ->
        Helpers.warn("Stacktrace depth: #{value}")

      true ->
        Helpers.warn("Could not parse STACKTRACE_DEPTH marker from response")
    end
  end
end
