defmodule CogElixir.CLITest do
  use ExUnit.Case, async: true

  alias CogElixir.CLI

  test "parses file list and output path" do
    assert {:ok, ["lib/a.ex", "lib/b.ex"], "/tmp/out.scip"} =
             CLI.parse(["--output", "/tmp/out.scip", "lib/a.ex", "lib/b.ex"])
  end

  test "handles file list before output path" do
    assert {:ok, ["lib/a.ex", "lib/b.ex"], "/tmp/out.scip"} =
             CLI.parse(["lib/a.ex", "lib/b.ex", "--output", "/tmp/out.scip"])
  end

  test "returns error when no arguments" do
    assert {:error, _} = CLI.parse([])
  end

  test "returns error when missing output path" do
    assert {:error, _} = CLI.parse(["src/main.ex"])
  end

  test "returns error when missing files" do
    assert {:error, _} = CLI.parse(["--output", "/tmp/out.scip"])
  end
end
