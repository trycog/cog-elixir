defmodule DebugApp.Chain do
  @moduledoc "Nested function calls for stack frame inspection testing."

  def start do
    x = 10
    result = middle(x)
    result
  end

  def middle(a) do
    b = a + 20
    result = bottom(b)
    result
  end

  def bottom(c) do
    d = c + 30
    d
  end
end
