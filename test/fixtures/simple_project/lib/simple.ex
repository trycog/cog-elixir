defmodule Simple do
  @moduledoc "A simple module"

  defstruct name: nil, age: 0

  @doc "Greets a person"
  def greet(name) do
    "Hello, #{name}!"
  end

  def add(a, b) do
    a + b
  end
end
