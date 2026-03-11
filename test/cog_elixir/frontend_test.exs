defmodule CogElixir.FrontendTest do
  use ExUnit.Case, async: true

  alias CogElixir.Frontend

  test "classifies template paths" do
    assert Frontend.classify_path("lib/demo.ex") == :elixir
    assert Frontend.classify_path("lib/demo.exs") == :elixir
    assert Frontend.classify_path("lib/demo.eex") == :eex
    assert Frontend.classify_path("lib/demo.html.eex") == :eex
    assert Frontend.classify_path("lib/demo.heex") == :heex
    assert Frontend.classify_path("lib/demo.html.heex") == :heex
  end

  test "indexes eex calls and assigns" do
    doc = Frontend.analyze("<%= foo(bar) %>\n<%= @name %>", "demo", "lib/demo.eex")

    assert Enum.any?(doc.occurrences, &String.contains?(&1.symbol, "Unknown#foo(1)."))
    assert Enum.any?(doc.symbols, &(&1.display_name == "@name"))
    assert Enum.any?(doc.symbols, &(&1.display_name == "demo.eex"))
  end

  test "indexes heex expressions and components" do
    source =
      "<div><%= foo(bar) %></div>\n<.input field={@form[:email]} />\n<MyAppWeb.Core.input />"

    doc = Frontend.analyze(source, "demo", "lib/demo.heex")

    assert Enum.any?(doc.occurrences, &String.contains?(&1.symbol, "Unknown#foo(1)."))
    assert Enum.any?(doc.symbols, &(&1.display_name == "input"))
    assert Enum.any?(doc.symbols, &(&1.display_name == "MyAppWeb.Core.input"))
    assert Enum.any?(doc.symbols, &(&1.display_name == "@form"))

    local_component_occurrence =
      Enum.find(doc.occurrences, &String.contains?(&1.symbol, "Unknown#input(1)."))

    module_component_occurrence =
      Enum.find(doc.occurrences, &String.contains?(&1.symbol, "`MyAppWeb.Core`#input(1)."))

    assert local_component_occurrence.range == [1, 2, 7]
    assert module_component_occurrence.range == [2, 15, 20]
  end

  test "indexes heex html attribute expressions and body assigns" do
    doc = Frontend.analyze(~S|<div class={foo(bar)}>{@name}</div>|, "demo", "lib/attrs.heex")

    assert Enum.any?(doc.occurrences, &String.contains?(&1.symbol, "Unknown#foo(1)."))
    assert Enum.any?(doc.symbols, &(&1.display_name == "@name"))

    assign_occurrence =
      Enum.find(doc.occurrences, &String.contains?(&1.symbol, "`lib/attrs.heex`#`@name`."))

    assert assign_occurrence.range == [0, 23, 28]
  end

  test "indexes heex slots and conditional/loop assigns" do
    source =
      ~S|<.table rows={@rows}><:col :let={row} label="Name">{row.name}</:col><div :if={@show}>Hi</div><div :for={item <- @items}>{item}</div></.table>|

    doc = Frontend.analyze(source, "demo", "lib/table.heex")

    assert Enum.any?(doc.symbols, &(&1.display_name == ":col"))
    assert Enum.any?(doc.symbols, &(&1.display_name == "@rows"))
    assert Enum.any?(doc.symbols, &(&1.display_name == "@show"))
    assert Enum.any?(doc.symbols, &(&1.display_name == "@items"))
    assert Enum.any?(doc.symbols, &(&1.display_name == "table"))
    assert Enum.any?(doc.symbols, &(&1.display_name == "row"))
    assert Enum.any?(doc.symbols, &(&1.display_name == "item"))

    slot_occurrence =
      Enum.find(doc.occurrences, &String.contains?(&1.symbol, "`lib/table.heex`#`:col`."))

    assert slot_occurrence.range == [0, 22, 26]
  end
end
