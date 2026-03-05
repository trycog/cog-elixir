defmodule Mix.Tasks.Integration do
  @moduledoc "Run all integration tests"
  @shortdoc "Run all integration tests"
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    IO.puts("========================================")
    IO.puts(" cog-elixir Integration Tests")
    IO.puts("========================================")

    IO.puts("")
    IO.puts(">>> Running code index tests...")
    IO.puts("")
    code_index_result = Mix.Tasks.Integration.CodeIndex.run([])

    IO.puts("")
    IO.puts("----------------------------------------")
    IO.puts("")
    IO.puts(">>> Running debugger tests...")
    IO.puts("")
    debugger_result = Mix.Tasks.Integration.Debugger.run([])

    IO.puts("")
    IO.puts("========================================")

    if code_index_result == :error or debugger_result == :error do
      IO.puts(" SOME SUITES FAILED")
      IO.puts("========================================")
      exit({:shutdown, 1})
    else
      IO.puts(" ALL SUITES PASSED")
      IO.puts("========================================")
    end
  end
end
