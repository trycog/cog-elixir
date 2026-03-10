defmodule Mix.Tasks.Integration.Debugger do
  @moduledoc "Integration tests for cog debugger via claude -p"
  @shortdoc "Run debugger integration tests"
  use Mix.Task

  alias Mix.Tasks.Integration.Helpers

  @skip_tests [
    "Full debug session via claude -p",
    "Struct inspection debug session",
    "Stepping workflow",
    "Conditional breakpoint",
    "Multi-breakpoint session",
    "Exception handling",
    "Stack frame inspection",
    "Variable mutation"
  ]

  @debug_tools "mcp__cog__cog_debug_launch,mcp__cog__cog_debug_breakpoint,mcp__cog__cog_debug_run,mcp__cog__cog_debug_inspect,mcp__cog__cog_debug_stacktrace,mcp__cog__cog_debug_stop"
  @struct_tools "mcp__cog__cog_debug_launch,mcp__cog__cog_debug_breakpoint,mcp__cog__cog_debug_run,mcp__cog__cog_debug_inspect,mcp__cog__cog_debug_stop"
  @stepping_tools "mcp__cog__cog_debug_launch,mcp__cog__cog_debug_breakpoint,mcp__cog__cog_debug_run,mcp__cog__cog_debug_inspect,mcp__cog__cog_debug_stop"
  @exception_tools "mcp__cog__cog_debug_launch,mcp__cog__cog_debug_breakpoint,mcp__cog__cog_debug_run,mcp__cog__cog_debug_inspect,mcp__cog__cog_debug_stacktrace,mcp__cog__cog_debug_stop"
  @scopes_tools "mcp__cog__cog_debug_launch,mcp__cog__cog_debug_breakpoint,mcp__cog__cog_debug_run,mcp__cog__cog_debug_inspect,mcp__cog__cog_debug_stacktrace,mcp__cog__cog_debug_scopes,mcp__cog__cog_debug_stop"
  @mutation_tools "mcp__cog__cog_debug_launch,mcp__cog__cog_debug_breakpoint,mcp__cog__cog_debug_run,mcp__cog__cog_debug_inspect,mcp__cog__cog_debug_set_variable,mcp__cog__cog_debug_stop"

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
      test_stepping_workflow(work_dir)
      test_conditional_breakpoint(work_dir)
      test_multi_breakpoint(work_dir)
      test_exception_handling(work_dir)
      test_stack_frame_inspection(work_dir)
      test_variable_mutation(work_dir)

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

  # Test 3: Stepping workflow
  defp test_stepping_workflow(work_dir) do
    IO.puts("--- Test: Stepping workflow ---")

    prompt = """
    You are testing a debugger. Do NOT delegate to subagents. Use the MCP tools directly yourself. Follow these steps EXACTLY:

    1. Call cog_debug_launch with: program="mix", args=["run", "-e", "DebugApp.Stepper.sequential()"], language="elixir", cwd="#{work_dir}", stop_on_entry=false
    2. Call cog_debug_breakpoint with: session_id, action="set", file="#{work_dir}/lib/debug_app/stepper.ex", line=5
    3. Call cog_debug_run with: session_id, action="continue"
       - Record whether stop_reason is "breakpoint"
    4. Call cog_debug_run with: session_id, action="step_over"
    5. Call cog_debug_inspect with: session_id, expression="a"
       - Record the value of a
    6. Call cog_debug_run with: session_id, action="step_over"
    7. Call cog_debug_inspect with: session_id, expression="b"
       - Record the value of b
    8. Call cog_debug_run with: session_id, action="step_over"
    9. Call cog_debug_inspect with: session_id, expression="c"
       - Record the value of c
    10. Call cog_debug_stop with: session_id

    After completing all steps, output EXACTLY these markers (each on its own line):
    STEP_BREAKPOINT_HIT: yes or no
    STEP_A_VALUE: <value of a>
    STEP_B_VALUE: <value of b>
    STEP_C_VALUE: <value of c>
    STEP_SESSION_DONE: yes or no

    Do not output anything else after the markers.\
    """

    {exit_code, resp} =
      Helpers.cmd(
        "claude",
        ["-p", prompt, "--allowedTools", @stepping_tools],
        cd: work_dir,
        timeout: 180_000
      )

    IO.puts("  claude exit code: #{exit_code}")
    IO.puts("  claude response length: #{String.length(resp)}")
    IO.puts("  claude response:")
    IO.puts("  ---")
    IO.puts(resp)
    IO.puts("  ---")

    bp_hit = parse_marker(resp, "STEP_BREAKPOINT_HIT")
    a_val = parse_marker(resp, "STEP_A_VALUE")
    b_val = parse_marker(resp, "STEP_B_VALUE")
    c_val = parse_marker(resp, "STEP_C_VALUE")
    done = parse_marker(resp, "STEP_SESSION_DONE")

    evaluate_marker(bp_hit, "yes", "Step breakpoint was hit", "STEP_BREAKPOINT_HIT")
    evaluate_marker(a_val, "1", "Step a=1 after first step_over", "STEP_A_VALUE")
    evaluate_marker(b_val, "2", "Step b=2 after second step_over", "STEP_B_VALUE")
    evaluate_marker(c_val, "3", "Step c=3 after third step_over", "STEP_C_VALUE")
    evaluate_marker(done, "yes", "Stepping session completed", "STEP_SESSION_DONE")
  end

  # Test 4: Conditional breakpoint
  defp test_conditional_breakpoint(work_dir) do
    IO.puts("--- Test: Conditional breakpoint ---")

    prompt = """
    You are testing a debugger. Do NOT delegate to subagents. Use the MCP tools directly yourself. Follow these steps EXACTLY:

    1. Call cog_debug_launch with: program="mix", args=["run", "-e", "DebugApp.Math.factorial(5)"], language="elixir", cwd="#{work_dir}", stop_on_entry=false
    2. Call cog_debug_breakpoint with: session_id, action="set", file="#{work_dir}/lib/debug_app/math.ex", line=11, condition="n == 3"
       - Record whether the breakpoint response has verified=true
    3. Call cog_debug_run with: session_id, action="continue"
       - Record the stop_reason
    4. Call cog_debug_inspect with: session_id, expression="n"
       - Record the value of n (should be 3 if conditional breakpoint worked)
    5. Call cog_debug_stacktrace with: session_id
    6. Call cog_debug_stop with: session_id

    After completing all steps, output EXACTLY these markers (each on its own line):
    COND_BP_VERIFIED: <true or false>
    COND_STOP_REASON: <stop_reason from run>
    COND_N_VALUE: <value of n>
    COND_SESSION_DONE: yes or no

    Do not output anything else after the markers.\
    """

    {exit_code, resp} =
      Helpers.cmd(
        "claude",
        ["-p", prompt, "--allowedTools", @debug_tools],
        cd: work_dir,
        timeout: 180_000
      )

    IO.puts("  claude exit code: #{exit_code}")
    IO.puts("  claude response length: #{String.length(resp)}")
    IO.puts("  claude response:")
    IO.puts("  ---")
    IO.puts(resp)
    IO.puts("  ---")

    bp_verified = parse_marker(resp, "COND_BP_VERIFIED")
    stop_reason = parse_marker(resp, "COND_STOP_REASON")
    if bp_verified, do: IO.puts("  [diag] conditional bp verified: #{bp_verified}")
    if stop_reason, do: IO.puts("  [diag] stop_reason: #{stop_reason}")

    n_val = parse_marker(resp, "COND_N_VALUE")
    done = parse_marker(resp, "COND_SESSION_DONE")

    evaluate_marker(n_val, "3", "Conditional breakpoint fired at n=3", "COND_N_VALUE")
    evaluate_marker(done, "yes", "Conditional breakpoint session completed", "COND_SESSION_DONE")
  end

  # Test 5: Multi-breakpoint session
  defp test_multi_breakpoint(work_dir) do
    IO.puts("--- Test: Multi-breakpoint session ---")

    prompt = """
    You are testing a debugger. Do NOT delegate to subagents. Use the MCP tools directly yourself. Follow these steps EXACTLY:

    1. Call cog_debug_launch with: program="mix", args=["run", "-e", "DebugApp.Runner.run()"], language="elixir", cwd="#{work_dir}", stop_on_entry=false
    2. Call cog_debug_breakpoint with: session_id, action="set", file="#{work_dir}/lib/debug_app/runner.ex", line=9
    3. Call cog_debug_breakpoint with: session_id, action="set", file="#{work_dir}/lib/debug_app/runner.ex", line=12
    4. Call cog_debug_breakpoint with: session_id, action="set", file="#{work_dir}/lib/debug_app/runner.ex", line=14
    5. Call cog_debug_run with: session_id, action="continue"
    6. Call cog_debug_stacktrace with: session_id
       - Record the line number of the topmost frame (should be 9)
    7. Call cog_debug_run with: session_id, action="continue"
    8. Call cog_debug_stacktrace with: session_id
       - Record the line number of the topmost frame (should be 12)
    9. Call cog_debug_run with: session_id, action="continue"
    10. Call cog_debug_stacktrace with: session_id
        - Record the line number of the topmost frame (should be 14)
    11. Call cog_debug_stop with: session_id

    After completing all steps, output EXACTLY these markers (each on its own line):
    MULTI_BP1_LINE: <line number at first stop>
    MULTI_BP2_LINE: <line number at second stop>
    MULTI_BP3_LINE: <line number at third stop>
    MULTI_SESSION_DONE: yes or no

    Do not output anything else after the markers.\
    """

    {exit_code, resp} =
      Helpers.cmd(
        "claude",
        ["-p", prompt, "--allowedTools", @debug_tools],
        cd: work_dir,
        timeout: 180_000
      )

    IO.puts("  claude exit code: #{exit_code}")
    IO.puts("  claude response length: #{String.length(resp)}")
    IO.puts("  claude response:")
    IO.puts("  ---")
    IO.puts(resp)
    IO.puts("  ---")

    bp1 = parse_marker(resp, "MULTI_BP1_LINE")
    bp2 = parse_marker(resp, "MULTI_BP2_LINE")
    bp3 = parse_marker(resp, "MULTI_BP3_LINE")
    done = parse_marker(resp, "MULTI_SESSION_DONE")

    evaluate_marker(bp1, "9", "First breakpoint hit at line 9", "MULTI_BP1_LINE")
    evaluate_marker(bp2, "12", "Second breakpoint hit at line 12", "MULTI_BP2_LINE")
    evaluate_marker(bp3, "14", "Third breakpoint hit at line 14", "MULTI_BP3_LINE")
    evaluate_marker(done, "yes", "Multi-breakpoint session completed", "MULTI_SESSION_DONE")
  end

  # Test 6: Exception handling
  # Uses a line breakpoint on the raise line since ElixirLS does not
  # reliably support DAP set_exception / filters=["raised"].
  defp test_exception_handling(work_dir) do
    IO.puts("--- Test: Exception handling ---")

    prompt = """
    You are testing a debugger. Do NOT delegate to subagents. Use the MCP tools directly yourself. Follow these steps EXACTLY:

    1. Call cog_debug_launch with: program="mix", args=["run", "-e", "DebugApp.Errors.risky_operation(nil)"], language="elixir", cwd="#{work_dir}", stop_on_entry=false
    2. Call cog_debug_breakpoint with: session_id, action="set", file="#{work_dir}/lib/debug_app/errors.ex", line=5
    3. Call cog_debug_run with: session_id, action="continue"
       - Record the stop_reason (should be "breakpoint")
    4. Call cog_debug_inspect with: session_id, expression="input"
       - Record the value of input (should be nil)
    5. Call cog_debug_stacktrace with: session_id
       - Record the number of frames
    6. Call cog_debug_stop with: session_id

    After completing all steps, output EXACTLY these markers (each on its own line):
    EXC_STOP_REASON: <stop_reason from run, e.g. breakpoint, timeout, exited>
    EXC_STOPPED: yes or no (was stop_reason "breakpoint"?)
    EXC_INPUT_VALUE: <the value of input, e.g. nil, null, or the actual value>
    EXC_STACK_DEPTH: <number of frames in stacktrace>
    EXC_SESSION_DONE: yes or no

    Do not output anything else after the markers.\
    """

    {exit_code, resp} =
      Helpers.cmd(
        "claude",
        ["-p", prompt, "--allowedTools", @exception_tools],
        cd: work_dir,
        timeout: 180_000
      )

    IO.puts("  claude exit code: #{exit_code}")
    IO.puts("  claude response length: #{String.length(resp)}")
    IO.puts("  claude response:")
    IO.puts("  ---")
    IO.puts(resp)
    IO.puts("  ---")

    stop_reason = parse_marker(resp, "EXC_STOP_REASON")
    if stop_reason, do: IO.puts("  [diag] exception stop_reason: #{stop_reason}")

    stopped = parse_marker(resp, "EXC_STOPPED")
    input_val = parse_marker(resp, "EXC_INPUT_VALUE")
    stack_depth = parse_marker(resp, "EXC_STACK_DEPTH")
    done = parse_marker(resp, "EXC_SESSION_DONE")

    evaluate_marker(stopped, "yes", "Exception-path breakpoint hit", "EXC_STOPPED")
    evaluate_nil_marker(input_val, "Input is nil at breakpoint", "EXC_INPUT_VALUE")
    evaluate_stack_frame_n(stack_depth, "EXC_STACK_DEPTH")
    evaluate_marker(done, "yes", "Exception handling session completed", "EXC_SESSION_DONE")
  end

  # Test 7: Stack frame inspection
  # Uses a chain of distinct functions (start → middle → bottom) so that
  # the BEAM stacktrace contains separate named frames with different variables.
  defp test_stack_frame_inspection(work_dir) do
    IO.puts("--- Test: Stack frame inspection ---")

    prompt = """
    You are testing a debugger. Do NOT delegate to subagents. Use the MCP tools directly yourself. Follow these steps EXACTLY:

    1. Call cog_debug_launch with: program="mix", args=["run", "-e", "DebugApp.Chain.start()"], language="elixir", cwd="#{work_dir}", stop_on_entry=false
    2. Call cog_debug_breakpoint with: session_id, action="set", file="#{work_dir}/lib/debug_app/chain.ex", line=17
    3. Call cog_debug_run with: session_id, action="continue"
    4. Call cog_debug_stacktrace with: session_id
       - The response has an array of frames. Note the "id" of the SECOND frame (index 1).
    5. Call cog_debug_inspect with: session_id, expression="c"
       - Record as STACK_TOP_VAR.
    6. Call cog_debug_inspect with: session_id, expression="a", frame_id=<id of the SECOND frame from step 4>
       - You MUST pass the frame_id parameter.
       - Record as STACK_DEEPER_VAR.
    7. Call cog_debug_stop with: session_id

    Output EXACTLY these markers:
    STACK_TOP_VAR: <value of c>
    STACK_DEEPER_VAR: <value of a>
    STACK_SESSION_DONE: yes or no
    """

    {exit_code, resp} =
      Helpers.cmd(
        "claude",
        ["-p", prompt, "--allowedTools", @scopes_tools],
        cd: work_dir,
        timeout: 300_000
      )

    IO.puts("  claude exit code: #{exit_code}")
    IO.puts("  claude response length: #{String.length(resp)}")
    IO.puts("  claude response:")
    IO.puts("  ---")
    IO.puts(resp)
    IO.puts("  ---")

    top_var = parse_marker(resp, "STACK_TOP_VAR")
    deeper_var = parse_marker(resp, "STACK_DEEPER_VAR")
    done = parse_marker(resp, "STACK_SESSION_DONE")

    evaluate_marker(top_var, "30", "Top frame c=30 (in bottom)", "STACK_TOP_VAR")
    evaluate_marker(deeper_var, "10", "Deeper frame a=10 (in middle)", "STACK_DEEPER_VAR")
    evaluate_marker(done, "yes", "Stack frame inspection completed", "STACK_SESSION_DONE")
  end

  # Test 8: Variable mutation
  defp test_variable_mutation(work_dir) do
    IO.puts("--- Test: Variable mutation ---")

    prompt = """
    You are testing a debugger. Do NOT delegate to subagents. Use the MCP tools directly yourself. Follow these steps EXACTLY:

    1. Call cog_debug_launch with: program="mix", args=["run", "-e", "DebugApp.Stepper.sequential()"], language="elixir", cwd="#{work_dir}", stop_on_entry=false
    2. Call cog_debug_breakpoint with: session_id, action="set", file="#{work_dir}/lib/debug_app/stepper.ex", line=7
    3. Call cog_debug_run with: session_id, action="continue"
       - We should stop at line 7 (c = a + b), where a=1 and b=2
    4. Call cog_debug_inspect with: session_id, expression="a"
       - Record as MUT_A_BEFORE (should be 1)
    5. Call cog_debug_set_variable with: session_id, variable="a", value="10"
    6. Call cog_debug_inspect with: session_id, expression="a"
       - Record as MUT_A_AFTER (should be 10 if mutation worked)
    7. Call cog_debug_run with: session_id, action="step_over"
    8. Call cog_debug_inspect with: session_id, expression="c"
       - Record as MUT_C_VALUE (should be 12 if mutation was effective, or 3 if BEAM ignored it)
    9. Call cog_debug_stop with: session_id

    After completing all steps, output EXACTLY these markers (each on its own line):
    MUT_A_BEFORE: <value of a before mutation>
    MUT_A_AFTER: <value of a after set_variable>
    MUT_C_VALUE: <value of c after step_over>
    MUT_SESSION_DONE: yes or no

    Do not output anything else after the markers.\
    """

    {exit_code, resp} =
      Helpers.cmd(
        "claude",
        ["-p", prompt, "--allowedTools", @mutation_tools],
        cd: work_dir,
        timeout: 180_000
      )

    IO.puts("  claude exit code: #{exit_code}")
    IO.puts("  claude response length: #{String.length(resp)}")
    IO.puts("  claude response:")
    IO.puts("  ---")
    IO.puts(resp)
    IO.puts("  ---")

    a_before = parse_marker(resp, "MUT_A_BEFORE")
    a_after = parse_marker(resp, "MUT_A_AFTER")
    c_val = parse_marker(resp, "MUT_C_VALUE")
    done = parse_marker(resp, "MUT_SESSION_DONE")

    evaluate_marker(a_before, "1", "Variable a=1 before mutation", "MUT_A_BEFORE")
    evaluate_marker(a_after, "10", "Variable a=10 after set_variable", "MUT_A_AFTER")
    evaluate_mutation_result(c_val, "MUT_C_VALUE")
    evaluate_marker(done, "yes", "Variable mutation session completed", "MUT_SESSION_DONE")
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

  defp evaluate_nil_marker(value, pass_msg, marker_name) do
    cond do
      value in ["nil", "null"] -> Helpers.pass(pass_msg)
      value != nil -> Helpers.warn("#{marker_name}: #{value} (expected nil)")
      true -> Helpers.warn("Could not parse #{marker_name} marker from response")
    end
  end

  defp evaluate_stack_frame_n(value, marker_name) do
    cond do
      value != nil and value != "0" and value != "unknown" ->
        Helpers.pass("Stack depth > 0 (depth: #{value})")

      value != nil ->
        Helpers.warn("#{marker_name}: #{value}")

      true ->
        Helpers.warn("Could not parse #{marker_name} marker from response")
    end
  end

  defp evaluate_mutation_result(value, marker_name) do
    cond do
      value == "12" ->
        Helpers.pass("Variable mutation effective: c=12 (a was mutated to 10)")

      value == "3" ->
        Helpers.warn("#{marker_name}: c=3 (BEAM ignored mutation, a+b=1+2=3)")

      value != nil ->
        Helpers.warn("#{marker_name}: c=#{value} (unexpected)")

      true ->
        Helpers.warn("Could not parse #{marker_name} marker from response")
    end
  end
end
