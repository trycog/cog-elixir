defmodule DebugApp.Math do
  @moduledoc """
  Mathematical functions useful for testing debugger breakpoints
  and stack inspection with recursive calls.
  """

  @doc "Compute the factorial of n (n >= 0)."
  def factorial(0), do: 1

  def factorial(n) when n > 0 do
    result = n * factorial(n - 1)
    result
  end

  @doc "Compute the nth Fibonacci number (0-indexed)."
  def fibonacci(n) when n >= 0 do
    do_fibonacci(n, 0, 1)
  end

  defp do_fibonacci(0, acc, _next), do: acc

  defp do_fibonacci(n, acc, next) do
    do_fibonacci(n - 1, next, acc + next)
  end
end
