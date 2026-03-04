defmodule CogElixir.WorkspaceTest do
  use ExUnit.Case, async: true

  alias CogElixir.Workspace

  @fixtures_dir Path.expand("../fixtures", __DIR__)

  test "find_root locates mix.exs directory" do
    file_path = Path.join(@fixtures_dir, "simple_project/lib/simple.ex")
    expected = Path.join(@fixtures_dir, "simple_project")
    assert Workspace.find_root(file_path) == expected
  end

  test "find_root works from nested directory" do
    dir_path = Path.join(@fixtures_dir, "simple_project/lib")
    expected = Path.join(@fixtures_dir, "simple_project")
    assert Workspace.find_root(dir_path) == expected
  end

  test "discover_project_name extracts app name" do
    root = Path.join(@fixtures_dir, "simple_project")
    assert Workspace.discover_project_name(root) == "simple_project"
  end

  test "discover_project_name extracts multi_module app name" do
    root = Path.join(@fixtures_dir, "multi_module")
    assert Workspace.discover_project_name(root) == "multi_module"
  end

  test "discover_project_name falls back to directory name" do
    assert Workspace.discover_project_name("/nonexistent/my_project") == "my_project"
  end
end
