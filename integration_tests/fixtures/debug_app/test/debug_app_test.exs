defmodule DebugAppTest do
  use ExUnit.Case, async: true

  test "new/1 creates a struct with the given name" do
    app = DebugApp.new("Test")
    assert app.name == "Test"
    assert app.items == []
  end

  test "add_item/2 prepends items" do
    app = DebugApp.new("Test")
    app = DebugApp.add_item(app, "a")
    app = DebugApp.add_item(app, "b")
    assert app.items == ["b", "a"]
  end

  test "greet/1 returns a greeting" do
    app = DebugApp.new("World")
    assert DebugApp.greet(app) == "Hello, World!"
  end

  test "factorial/1 computes correctly" do
    assert DebugApp.Math.factorial(0) == 1
    assert DebugApp.Math.factorial(5) == 120
  end

  test "fibonacci/1 computes correctly" do
    assert DebugApp.Math.fibonacci(0) == 0
    assert DebugApp.Math.fibonacci(1) == 1
    assert DebugApp.Math.fibonacci(8) == 21
  end

  test "Worker.handle/1 pattern matching" do
    assert DebugApp.Worker.handle({:ok, 42}) == {:processed, 42}
    assert DebugApp.Worker.handle({:error, :timeout}) == {:failed, :timeout}
    assert DebugApp.Worker.handle(:ping) == :pong
    assert DebugApp.Worker.handle("other") == :unknown
  end
end
