defmodule CogElixir.SymbolTest do
  use ExUnit.Case, async: true

  alias CogElixir.Symbol

  test "module_symbol with simple name" do
    assert Symbol.module_symbol("my_app", "MyModule") == "file . my_app unversioned MyModule#"
  end

  test "module_symbol with dotted name" do
    assert Symbol.module_symbol("my_app", "MyApp.Worker") ==
             "file . my_app unversioned `MyApp.Worker`#"
  end

  test "function_symbol" do
    assert Symbol.function_symbol("my_app", "MyModule", :greet, 1) ==
             "file . my_app unversioned MyModule#greet(1)."
  end

  test "function_symbol with special chars" do
    assert Symbol.function_symbol("my_app", "MyModule", :valid?, 1) ==
             "file . my_app unversioned MyModule#`valid?`(1)."
  end

  test "field_symbol" do
    assert Symbol.field_symbol("my_app", "MyModule", :name) ==
             "file . my_app unversioned MyModule#name."
  end

  test "attribute_symbol" do
    assert Symbol.attribute_symbol("my_app", "MyModule", :my_attr) ==
             "file . my_app unversioned MyModule#my_attr."
  end

  test "type_symbol" do
    assert Symbol.type_symbol("my_app", "MyModule", :t, 0) ==
             "file . my_app unversioned MyModule#t(0)."
  end

  test "local_symbol" do
    assert Symbol.local_symbol(0) == "local 0"
    assert Symbol.local_symbol(5) == "local 5"
  end
end
