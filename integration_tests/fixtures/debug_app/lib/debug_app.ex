defmodule DebugApp do
  @moduledoc """
  A sample application for integration testing cog-elixir.
  Provides a struct, various functions, and a runnable entry point.
  """

  defstruct [:name, :items]

  @doc "Create a new DebugApp struct with the given name."
  def new(name) do
    %DebugApp{name: name, items: []}
  end

  @doc "Add an item to the struct's items list."
  def add_item(%DebugApp{} = app, item) do
    %DebugApp{app | items: [item | app.items]}
  end

  @doc "Return a greeting string for the struct's name."
  def greet(%DebugApp{name: name}) do
    "Hello, #{name}!"
  end

  @doc "Run a sample workflow: create a struct, add items, and greet."
  def run do
    app = new("World")
    app = add_item(app, "alpha")
    app = add_item(app, "beta")
    greeting = greet(app)

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
