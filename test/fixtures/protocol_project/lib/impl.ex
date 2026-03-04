defimpl Describable, for: Map do
  def describe(map) do
    "A map with #{map_size(map)} keys"
  end
end
