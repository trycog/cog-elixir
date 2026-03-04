defmodule CogElixir.CLITest do
  use ExUnit.Case, async: true

  alias CogElixir.CLI

  test "parses file path and output path" do
    assert {:ok, "src/main.ex", "/tmp/out.scip"} =
             CLI.parse(["src/main.ex", "--output", "/tmp/out.scip"])
  end

  test "handles output before file path" do
    assert {:ok, "src/main.ex", "/tmp/out.scip"} =
             CLI.parse(["--output", "/tmp/out.scip", "src/main.ex"])
  end

  test "returns error when no arguments" do
    assert {:error, _} = CLI.parse([])
  end

  test "returns error when missing output path" do
    assert {:error, _} = CLI.parse(["src/main.ex"])
  end

  test "returns error when missing file path" do
    assert {:error, _} = CLI.parse(["--output", "/tmp/out.scip"])
  end
end
