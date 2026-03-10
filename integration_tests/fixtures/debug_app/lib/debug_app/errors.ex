defmodule DebugApp.Errors do
  @moduledoc "Functions that raise for exception breakpoint testing."

  def risky_operation(input) do
    validated = validate(input)
    process_validated(validated)
  end

  defp validate(nil), do: raise("input cannot be nil")
  defp validate(input), do: input

  defp process_validated(input), do: String.upcase(input)
end
