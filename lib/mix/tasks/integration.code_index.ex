defmodule Mix.Tasks.Integration.CodeIndex do
  @moduledoc "Integration tests for cog code:index"
  @shortdoc "Run code index integration tests"
  use Mix.Task

  alias Mix.Tasks.Integration.Helpers

  @skip_tests [
    "cog code:index exits with 0",
    "index.scip exists",
    "index.scip is non-empty",
    "escript output contains 'cog-elixir' tool identifier",
    "index.scip contains symbol 'DebugApp'",
    "index.scip contains symbol 'factorial'",
    "index.scip contains symbol 'fibonacci'",
    "index.scip contains symbol 'Worker'",
    "index.scip contains symbol 'Math'",
    "index.scip contains symbol 'greet'"
  ]

  @impl Mix.Task
  def run(_args) do
    Helpers.start_counters()

    IO.puts("")
    IO.puts("=== Code Index Integration Tests ===")
    IO.puts("")

    case Helpers.check_prerequisites(["cog"]) do
      {:missing, _} ->
        IO.puts("Skipping code index tests: 'cog' not found in PATH")
        Enum.each(@skip_tests, &Helpers.skip/1)
        Helpers.print_summary()

      :ok ->
        run_tests()
    end
  end

  defp run_tests do
    root_dir = File.cwd!()

    Helpers.with_fixture("code-index", fn work_dir ->
      # Create .cog/settings.json
      cog_dir = Path.join(work_dir, ".cog")
      File.mkdir_p!(cog_dir)

      File.write!(Path.join(cog_dir, "settings.json"), ~S"""
      {
        "code": {
          "index": [
            "lib/**/*.ex",
            "test/**/*.exs",
            "mix.exs"
          ]
        }
      }
      """)

      # Test 1: cog code:index succeeds
      IO.puts("--- Test: cog code:index succeeds ---")
      {exit_code, output} = Helpers.cmd("cog", ["code:index"], cd: work_dir)

      if exit_code == 0 do
        Helpers.pass("cog code:index exits with 0")
      else
        Helpers.fail("cog code:index exits with 0 (got exit #{exit_code})")
        IO.puts("  Output: #{output}")
      end

      # Test 2: index.scip created and non-empty
      IO.puts("--- Test: index.scip created and non-empty ---")
      scip_file = Path.join([work_dir, ".cog", "index.scip"])
      Helpers.assert_file_exists(scip_file, "index.scip exists")
      Helpers.assert_file_not_empty(scip_file, "index.scip is non-empty")

      # Test 3: Contains tool identifier via direct escript
      IO.puts("--- Test: index.scip contains tool identifier ---")
      escript = Path.join([root_dir, "bin", "cog-elixir"])

      if File.exists?(escript) do
        tool_check_out =
          Path.join(System.tmp_dir!(), "cog-elixir-toolcheck-#{:rand.uniform(999_999)}.scip")

        Helpers.cmd(
          escript,
          ["--output", tool_check_out, Path.join(work_dir, "lib/debug_app.ex")],
          cd: work_dir
        )

        if File.exists?(tool_check_out) do
          {strings_output, _} = System.cmd("strings", [tool_check_out])

          if String.contains?(strings_output, "cog-elixir") do
            Helpers.pass("escript output contains 'cog-elixir' tool identifier")
          else
            Helpers.fail("escript output contains 'cog-elixir' tool identifier")
          end
        else
          Helpers.fail("escript output contains 'cog-elixir' tool identifier (no output file)")
        end

        File.rm_rf(tool_check_out)
      else
        Helpers.skip("tool identifier check (bin/cog-elixir not found)")
      end

      # Test 4: Contains expected symbols
      IO.puts("--- Test: index.scip contains expected symbols ---")

      if File.exists?(scip_file) do
        {scip_strings, _} = System.cmd("strings", [scip_file])

        for symbol <- ~w(DebugApp factorial fibonacci Worker Math greet) do
          if String.contains?(scip_strings, symbol) do
            Helpers.pass("index.scip contains symbol '#{symbol}'")
          else
            Helpers.fail("index.scip contains symbol '#{symbol}'")
          end
        end
      else
        Helpers.skip("index.scip contains expected symbols (file missing)")
      end

      # Test 5: Direct escript invocation
      IO.puts("--- Test: Direct escript invocation ---")

      if File.exists?(escript) do
        escript_out =
          Path.join(System.tmp_dir!(), "cog-elixir-direct-#{:rand.uniform(999_999)}.scip")

        {escript_exit, _} =
          Helpers.cmd(escript, ["--output", escript_out, Path.join(work_dir, "lib/debug_app.ex")],
            cd: work_dir
          )

        Helpers.assert_exit_code(escript_exit, 0, "escript invocation exits with 0")
        Helpers.assert_file_not_empty(escript_out, "escript produces non-empty output")
        File.rm_rf(escript_out)
      else
        Helpers.skip("Direct escript invocation (bin/cog-elixir not found or not executable)")
      end

      # Test 6: MCP code explore via claude -p
      IO.puts("--- Test: MCP code explore via claude -p ---")

      if System.find_executable("claude") == nil do
        Helpers.skip("MCP code explore (claude not found in PATH)")
      else
        # cog_code_status
        {_, status_resp} =
          Helpers.cmd(
            "claude",
            [
              "-p",
              "Call the cog_code_status tool and report the result. Output ONLY the raw tool result, nothing else.",
              "--allowedTools",
              "mcp__cog__cog_code_status"
            ],
            cd: work_dir,
            timeout: 120_000
          )

        if Regex.match?(~r/index|scip|ready|status/i, status_resp) do
          Helpers.pass("cog_code_status returns index information")
        else
          first_lines = status_resp |> String.split("\n") |> Enum.take(5) |> Enum.join("\n")
          Helpers.warn("cog_code_status response unclear: #{first_lines}")
        end

        # cog_code_explore
        {_, explore_resp} =
          Helpers.cmd(
            "claude",
            [
              "-p",
              "Call the cog_code_explore tool to search for the symbol 'DebugApp'. Report ONLY what you find, listing any symbols or definitions.",
              "--allowedTools",
              "mcp__cog__cog_code_explore"
            ],
            cd: work_dir,
            timeout: 120_000
          )

        if String.contains?(explore_resp, "DebugApp") do
          Helpers.pass("cog_code_explore finds DebugApp")
        else
          first_lines = explore_resp |> String.split("\n") |> Enum.take(5) |> Enum.join("\n")
          Helpers.warn("cog_code_explore did not find DebugApp: #{first_lines}")
        end
      end

      # Summary
      Helpers.print_summary()
    end)
  end
end
