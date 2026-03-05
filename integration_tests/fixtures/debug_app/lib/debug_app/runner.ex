defmodule DebugApp.Runner do
  @moduledoc """
  Runner module for debug testing.
  Separated from DebugApp to avoid potential issues with breakpoints
  in modules that define defstruct.
  """

  def run do
    app = DebugApp.new("World")
    app = DebugApp.add_item(app, "alpha")
    app = DebugApp.add_item(app, "beta")
    greeting = DebugApp.greet(app)

    result = DebugApp.Math.factorial(5)
    fib = DebugApp.Math.fibonacci(8)

    %{
      app: app,
      greeting: greeting,
      factorial_5: result,
      fibonacci_8: fib
    }
  end
end
