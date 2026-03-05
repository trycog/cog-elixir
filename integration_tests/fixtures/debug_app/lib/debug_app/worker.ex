defmodule DebugApp.Worker do
  @moduledoc """
  A worker module that exercises alias, import, type specs,
  and pattern matching for code indexer testing.
  """

  alias DebugApp
  import Enum, only: [map: 2, filter: 2]

  @type state :: %{status: atom(), data: list()}

  @doc "Initialize a new worker state."
  def init do
    %{status: :idle, data: []}
  end

  @doc "Process a list of items using imported Enum functions."
  def process(items) when is_list(items) do
    items
    |> filter(fn item -> item != nil end)
    |> map(fn item -> transform(item) end)
  end

  @doc "Create a DebugApp struct via alias and process its items."
  def run_with_app(name, items) do
    app = DebugApp.new(name)

    app =
      Enum.reduce(items, app, fn item, acc ->
        DebugApp.add_item(acc, item)
      end)

    DebugApp.greet(app)
  end

  @doc "Handle different input patterns."
  def handle({:ok, value}), do: {:processed, value}
  def handle({:error, reason}), do: {:failed, reason}
  def handle(:ping), do: :pong
  def handle(_other), do: :unknown

  defp transform(item) when is_binary(item), do: String.upcase(item)
  defp transform(item) when is_number(item), do: item * 2
  defp transform(item), do: item
end
