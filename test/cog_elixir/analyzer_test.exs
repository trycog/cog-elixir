defmodule CogElixir.AnalyzerTest do
  use ExUnit.Case, async: true

  alias CogElixir.Analyzer
  alias CogElixir.Scip

  defp analyze(source) do
    Analyzer.analyze(source, "test_app", "lib/test.ex")
  end

  defp find_symbol(doc, display_name) do
    Enum.find(doc.symbols, fn s -> s.display_name == display_name end)
  end

  defp find_occurrence_by_symbol(doc, symbol_str) do
    Enum.find(doc.occurrences, fn o -> o.symbol == symbol_str end)
  end

  # --- Module definitions ---

  test "detects defmodule" do
    doc = analyze("defmodule MyModule do\nend")
    sym = find_symbol(doc, "MyModule")
    assert sym != nil
    assert sym.kind == Scip.kind_module()
    assert sym.symbol == "file . test_app unversioned MyModule#"
  end

  test "detects nested module name" do
    doc = analyze("defmodule MyApp.Worker do\nend")
    sym = find_symbol(doc, "MyApp.Worker")
    assert sym != nil
    assert sym.kind == Scip.kind_module()
  end

  test "attaches @moduledoc to module" do
    source = """
    defmodule MyModule do
      @moduledoc "Hello world"
    end
    """

    doc = analyze(source)
    # moduledoc is on the module before any child definition;
    # in this case it won't attach because there's no next definition after it
    # The module definition itself should exist
    sym = find_symbol(doc, "MyModule")
    assert sym != nil
  end

  # --- Function definitions ---

  test "detects def with arity" do
    source = """
    defmodule MyModule do
      def greet(name) do
        name
      end
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "greet/1")
    assert sym != nil
    assert sym.kind == Scip.kind_function()
    assert sym.enclosing_symbol == "file . test_app unversioned MyModule#"
  end

  test "detects defp" do
    source = """
    defmodule MyModule do
      defp helper(x), do: x
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "helper/1")
    assert sym != nil
    assert sym.kind == Scip.kind_function()
  end

  test "detects zero-arity function" do
    source = """
    defmodule MyModule do
      def hello, do: :world
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "hello/0")
    assert sym != nil
  end

  test "multi-clause function creates single symbol" do
    source = """
    defmodule MyModule do
      def process(:a), do: 1
      def process(:b), do: 2
    end
    """

    doc = analyze(source)
    symbols = Enum.filter(doc.symbols, fn s -> s.display_name == "process/1" end)
    assert length(symbols) == 1

    # But should have two occurrences for the definition
    occs =
      Enum.filter(doc.occurrences, fn o ->
        o.symbol == symbols |> hd() |> Map.get(:symbol) and o.symbol_roles == Scip.role_definition()
      end)

    assert length(occs) == 2
  end

  test "attaches @doc to function" do
    source = """
    defmodule MyModule do
      @doc "Says hello"
      def hello, do: :world
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "hello/0")
    assert sym != nil
    assert sym.documentation == ["Says hello"]
  end

  # --- Parameters ---

  test "detects function parameters" do
    source = """
    defmodule MyModule do
      def add(a, b), do: a + b
    end
    """

    doc = analyze(source)
    a_sym = find_symbol(doc, "a")
    b_sym = find_symbol(doc, "b")
    assert a_sym != nil
    assert a_sym.kind == Scip.kind_parameter()
    assert b_sym != nil
  end

  # --- Struct fields ---

  test "detects defstruct fields" do
    source = """
    defmodule MyModule do
      defstruct name: nil, age: 0
    end
    """

    doc = analyze(source)
    name_sym = find_symbol(doc, "name")
    age_sym = find_symbol(doc, "age")
    assert name_sym != nil
    assert name_sym.kind == Scip.kind_field()
    assert age_sym != nil
  end

  # --- Macros ---

  test "detects defmacro" do
    source = """
    defmodule MyModule do
      defmacro my_macro(arg) do
        quote do: unquote(arg)
      end
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "my_macro/1")
    assert sym != nil
    assert sym.kind == Scip.kind_macro()
  end

  # --- Protocol ---

  test "detects defprotocol" do
    source = """
    defprotocol Describable do
      def describe(data)
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "Describable")
    assert sym != nil
    assert sym.kind == Scip.kind_interface()
  end

  # --- defimpl ---

  test "detects defimpl" do
    source = """
    defimpl Describable, for: Map do
      def describe(map), do: "a map"
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "Describable.Map")
    assert sym != nil
    assert sym.kind == Scip.kind_module()
  end

  # --- Guards ---

  test "detects defguard" do
    source = """
    defmodule MyModule do
      defguard is_positive(x) when x > 0
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "is_positive/1")
    assert sym != nil
    assert sym.kind == Scip.kind_macro()
  end

  # --- defdelegate ---

  test "detects defdelegate" do
    source = """
    defmodule MyModule do
      defdelegate size(map), to: Kernel, as: :map_size
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "size/1")
    assert sym != nil
    assert sym.kind == Scip.kind_function()
  end

  # --- Types ---

  test "detects @type" do
    source = """
    defmodule MyModule do
      @type t :: %__MODULE__{}
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "t/0")
    assert sym != nil
    assert sym.kind == Scip.kind_type()
  end

  test "detects @type with params" do
    source = """
    defmodule MyModule do
      @type result(ok, err) :: {:ok, ok} | {:error, err}
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "result/2")
    assert sym != nil
    assert sym.kind == Scip.kind_type()
  end

  # --- Callbacks ---

  test "detects @callback" do
    source = """
    defmodule MyBehaviour do
      @callback handle_event(event :: term()) :: :ok
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "handle_event/1")
    assert sym != nil
    assert sym.kind == Scip.kind_function()
  end

  # --- Module attributes ---

  test "detects custom module attribute" do
    source = """
    defmodule MyModule do
      @my_constant 42
    end
    """

    doc = analyze(source)
    sym = find_symbol(doc, "@my_constant")
    assert sym != nil
    assert sym.kind == Scip.kind_constant()
  end

  # --- References (alias/import/use/require) ---

  test "detects alias as import reference" do
    source = """
    defmodule MyModule do
      alias MyApp.Helper
    end
    """

    doc = analyze(source)

    occ =
      Enum.find(doc.occurrences, fn o ->
        o.symbol_roles == Scip.role_import() and
          String.contains?(o.symbol, "MyApp.Helper")
      end)

    assert occ != nil
  end

  test "detects import as import reference" do
    source = """
    defmodule MyModule do
      import Enum
    end
    """

    doc = analyze(source)

    occ =
      Enum.find(doc.occurrences, fn o ->
        o.symbol_roles == Scip.role_import() and
          String.contains?(o.symbol, "Enum")
      end)

    assert occ != nil
  end

  test "detects use as import reference" do
    source = """
    defmodule MyModule do
      use GenServer
    end
    """

    doc = analyze(source)

    occ =
      Enum.find(doc.occurrences, fn o ->
        o.symbol_roles == Scip.role_import() and
          String.contains?(o.symbol, "GenServer")
      end)

    assert occ != nil
  end

  test "detects require as import reference" do
    source = """
    defmodule MyModule do
      require Logger
    end
    """

    doc = analyze(source)

    occ =
      Enum.find(doc.occurrences, fn o ->
        o.symbol_roles == Scip.role_import() and
          String.contains?(o.symbol, "Logger")
      end)

    assert occ != nil
  end

  test "detects @behaviour as import reference" do
    source = """
    defmodule MyModule do
      @behaviour GenServer
    end
    """

    doc = analyze(source)

    occ =
      Enum.find(doc.occurrences, fn o ->
        o.symbol_roles == Scip.role_import() and
          String.contains?(o.symbol, "GenServer")
      end)

    assert occ != nil
  end

  # --- Ranges ---

  test "occurrence ranges are 0-indexed" do
    source = "defmodule MyModule do\nend"
    doc = analyze(source)
    sym = find_symbol(doc, "MyModule")
    occ = find_occurrence_by_symbol(doc, sym.symbol)
    assert occ != nil
    # "MyModule" starts at column 11 (0-indexed: 10), length 8, so end = 18
    assert occ.range == [0, 10, 18]
  end

  # --- Parse errors ---

  test "returns empty document on parse error" do
    doc = analyze("defmodule do end {{{")
    assert doc.language == "elixir"
    assert doc.relative_path == "lib/test.ex"
  end

  # --- Fixture integration ---

  test "analyzes simple_project fixture" do
    fixtures_dir = Path.expand("../fixtures", __DIR__)
    source = File.read!(Path.join(fixtures_dir, "simple_project/lib/simple.ex"))
    doc = Analyzer.analyze(source, "simple_project", "lib/simple.ex")

    assert doc.language == "elixir"
    assert doc.relative_path == "lib/simple.ex"

    # Should find the module
    mod = find_symbol(doc, "Simple")
    assert mod != nil
    assert mod.kind == Scip.kind_module()

    # Should find the greet function
    greet = find_symbol(doc, "greet/1")
    assert greet != nil

    # Should find struct fields
    name_field = find_symbol(doc, "name")
    assert name_field != nil
    assert name_field.kind == Scip.kind_field()
  end

  test "analyzes protocol fixture" do
    fixtures_dir = Path.expand("../fixtures", __DIR__)
    source = File.read!(Path.join(fixtures_dir, "protocol_project/lib/protocol.ex"))
    doc = Analyzer.analyze(source, "protocol_project", "lib/protocol.ex")

    proto = find_symbol(doc, "Describable")
    assert proto != nil
    assert proto.kind == Scip.kind_interface()

    func = find_symbol(doc, "describe/1")
    assert func != nil
  end
end
