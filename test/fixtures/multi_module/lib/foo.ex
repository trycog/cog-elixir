defmodule MultiModule.Foo do
  alias MultiModule.Bar

  def call_bar do
    Bar.hello()
  end
end
