defmodule CogElixir.Frontend.EExFile do
  @moduledoc false

  alias CogElixir.{Analyzer, Scip, Symbol}

  def analyze(source, package_name, relative_path) do
    owner = Symbol.template_symbol(package_name, relative_path)
    ast = EEx.compile_string(source, engine: EEx.SmartEngine, file: relative_path, line: 1)

    base_document(relative_path, owner)
    |> merge_document(
      Analyzer.analyze_ast(ast, source, package_name, relative_path, file_owner: owner)
    )
  end

  defp base_document(relative_path, owner) do
    %Scip.Document{
      language: "elixir",
      relative_path: relative_path,
      symbols: [
        %Scip.SymbolInformation{
          symbol: owner,
          kind: Scip.kind_module(),
          display_name: Path.basename(relative_path),
          enclosing_symbol: ""
        }
      ]
    }
  end

  defp merge_document(left, right) do
    %Scip.Document{
      language: left.language,
      relative_path: left.relative_path,
      occurrences:
        Enum.uniq_by(
          left.occurrences ++ right.occurrences,
          &{&1.range, &1.symbol, &1.symbol_roles}
        ),
      symbols: merge_symbols(left.symbols ++ right.symbols)
    }
  end

  defp merge_symbols(symbols) do
    symbols
    |> Enum.group_by(& &1.symbol)
    |> Enum.map(fn {_symbol, group} -> hd(group) end)
  end
end
