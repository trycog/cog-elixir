defmodule DebugApp.Stepper do
  @moduledoc "Sequential assignments for step-over testing."

  def sequential do
    a = 1
    b = 2
    c = a + b
    d = c * 2
    e = d + 10
    {a, b, c, d, e}
  end
end
