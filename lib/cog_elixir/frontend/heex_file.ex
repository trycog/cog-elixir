defmodule CogElixir.Frontend.HEExFile do
  @moduledoc false

  alias CogElixir.{Analyzer, Scip, Symbol}

  def analyze(source, package_name, relative_path) do
    owner = Symbol.template_symbol(package_name, relative_path)

    case compile_heex(source, relative_path) do
      {:ok, ast} ->
        base_document(relative_path, owner)
        |> merge_document(expression_documents(ast, source, package_name, relative_path, owner))
        |> merge_document(component_documents(ast, source, package_name, relative_path, owner))
        |> merge_document(assign_documents(ast, source, package_name, relative_path, owner))
        |> merge_document(slot_documents(ast, source, package_name, relative_path, owner))
        |> merge_document(
          local_binding_documents(ast, source, package_name, relative_path, owner)
        )

      {:error, _reason} ->
        base_document(relative_path, owner)
    end
  end

  defp compile_heex(source, relative_path) do
    {:ok,
     EEx.compile_string(source,
       engine: Phoenix.LiveView.TagEngine,
       line: 1,
       file: relative_path,
       caller: __ENV__,
       source: source,
       tag_handler: Phoenix.LiveView.HTMLEngine
     )}
  rescue
    error -> {:error, error}
  end

  defp expression_documents(ast, source, package_name, relative_path, owner) do
    ast
    |> collect_live_exprs()
    |> Kernel.++(collect_component_attr_exprs(ast))
    |> Enum.reduce(empty_document(relative_path), fn expr, acc ->
      case normalize_expr(expr) do
        :skip ->
          acc

        normalized ->
          merge_document(
            acc,
            Analyzer.analyze_ast(normalized, source, package_name, relative_path,
              file_owner: owner
            )
          )
      end
    end)
  end

  defp collect_live_exprs(ast) do
    {_ast, exprs} =
      Macro.prewalk(ast, [], fn
        {{:., _, [module, :live_to_iodata]}, _, [expr]} = node, acc ->
          case module do
            Phoenix.LiveView.Engine -> {node, [expr | acc]}
            {:__aliases__, _, [:Phoenix, :LiveView, :Engine]} -> {node, [expr | acc]}
            _ -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(exprs)
  end

  defp collect_component_attr_exprs(ast) do
    {_ast, exprs} =
      Macro.prewalk(ast, [], fn
        {{:., _, [module, :component]}, _, [_capture, assigns_ast, _caller]} = node, acc ->
          case module do
            Phoenix.LiveView.TagEngine ->
              {node, extract_assign_values(assigns_ast) ++ acc}

            {:__aliases__, _, [:Phoenix, :LiveView, :TagEngine]} ->
              {node, extract_assign_values(assigns_ast) ++ acc}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(exprs)
  end

  defp extract_assign_values({:%{}, _, pairs}) do
    Enum.flat_map(pairs, fn
      {:__changed__, _value} -> []
      {_key, value} -> [value]
      _ -> []
    end)
  end

  defp extract_assign_values(_), do: []

  defp normalize_expr({:safe, expr}), do: normalize_expr(expr)
  defp normalize_expr(safe: expr), do: normalize_expr(expr)

  defp normalize_expr({{:., _, [module, :component]}, _, _args})
       when module == Phoenix.LiveView.TagEngine do
    :skip
  end

  defp normalize_expr(
         {{:., _, [{:__aliases__, _, [:Phoenix, :LiveView, :TagEngine]}, :component]}, _, _args}
       ),
       do: :skip

  defp normalize_expr({{:., _, [module, function]}, _, [expr]})
       when function in [
              :class_attribute_encode,
              :empty_attribute_encode,
              :attributes_escape,
              :binary_encode
            ] do
    case module do
      Phoenix.LiveView.HTMLEngine -> normalize_expr(expr)
      {:__aliases__, _, [:Phoenix, :LiveView, :HTMLEngine]} -> normalize_expr(expr)
      _ -> {{:., [], [module, function]}, [], [expr]}
    end
  end

  defp normalize_expr({:%{}, _, pairs}) do
    {:%{}, [], Enum.reject(pairs, fn {key, _value} -> key == :__changed__ end)}
  end

  defp normalize_expr(expr), do: expr

  defp component_documents(ast, source, package_name, relative_path, owner) do
    ast
    |> collect_component_refs(source)
    |> Enum.reduce(empty_document(relative_path), fn {module_name, component_name, display_name,
                                                      range},
                                                     acc ->
      symbol = Symbol.component_symbol(package_name, module_name, component_name, 1)
      merge_document(acc, component_document(relative_path, owner, symbol, display_name, range))
    end)
  end

  defp collect_component_refs(ast, source) do
    {_ast, refs} =
      Macro.prewalk(ast, [], fn
        {:&, _, [{:/, _, [{name, meta, context}, 1]}]} = node, acc
        when is_atom(name) and is_atom(context) ->
          range = name_range(source, meta, Atom.to_string(name), "<.#{name}")
          {node, [{"Unknown", Atom.to_string(name), Atom.to_string(name), range} | acc]}

        {:&, _,
         [
           {:/, _,
            [
              {{:., fun_meta, [{:__aliases__, alias_meta, segments}, name]}, _, []},
              1
            ]}
         ]} = node,
        acc
        when is_list(segments) and is_atom(name) ->
          module_name = Enum.map_join(segments, ".", &Atom.to_string/1)
          component_name = Atom.to_string(name)

          range =
            name_range(
              source,
              fun_meta,
              component_name,
              "#{module_name}.#{component_name}",
              alias_meta
            )

          {node, [{module_name, component_name, "#{module_name}.#{component_name}", range} | acc]}

        node, acc ->
          {node, acc}
      end)

    refs
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp assign_documents(ast, source, package_name, relative_path, owner) do
    ast
    |> collect_assign_refs(source)
    |> Enum.reduce(empty_document(relative_path), fn {assign_name, range}, acc ->
      symbol =
        Symbol.template_assign_symbol(package_name, relative_path, String.to_atom(assign_name))

      merge_document(
        acc,
        %Scip.Document{
          language: "elixir",
          relative_path: relative_path,
          occurrences: [
            %Scip.Occurrence{range: range, symbol: symbol, symbol_roles: Scip.role_read()}
          ],
          symbols: [
            %Scip.SymbolInformation{
              symbol: symbol,
              kind: Scip.kind_constant(),
              display_name: "@#{assign_name}",
              enclosing_symbol: owner
            }
          ]
        }
      )
    end)
  end

  defp slot_documents(ast, source, package_name, relative_path, owner) do
    ast
    |> collect_slot_refs(source)
    |> Enum.reduce(empty_document(relative_path), fn {slot_name, range}, acc ->
      symbol = Symbol.template_slot_symbol(package_name, relative_path, slot_name)

      merge_document(
        acc,
        %Scip.Document{
          language: "elixir",
          relative_path: relative_path,
          occurrences: [
            %Scip.Occurrence{range: range, symbol: symbol, symbol_roles: Scip.role_read()}
          ],
          symbols: [
            %Scip.SymbolInformation{
              symbol: symbol,
              kind: Scip.kind_field(),
              display_name: ":#{slot_name}",
              enclosing_symbol: owner
            }
          ]
        }
      )
    end)
  end

  defp local_binding_documents(ast, source, package_name, relative_path, owner) do
    ast
    |> collect_local_bindings(source)
    |> Enum.reduce(empty_document(relative_path), fn {name, range, line}, acc ->
      symbol = Symbol.template_local_symbol(package_name, relative_path, name, line)

      merge_document(
        acc,
        %Scip.Document{
          language: "elixir",
          relative_path: relative_path,
          occurrences: [
            %Scip.Occurrence{range: range, symbol: symbol, symbol_roles: Scip.role_definition()}
          ],
          symbols: [
            %Scip.SymbolInformation{
              symbol: symbol,
              kind: Scip.kind_parameter(),
              display_name: name,
              enclosing_symbol: owner
            }
          ]
        }
      )
    end)
  end

  defp collect_assign_refs(ast, source) do
    {_ast, refs} =
      Macro.prewalk(ast, [], fn
        {{:., meta, [{:assigns, _, _}, assign_name]}, _, []} = node, acc
        when is_atom(assign_name) ->
          range = assign_range(source, meta, Atom.to_string(assign_name))
          {node, [{Atom.to_string(assign_name), range} | acc]}

        node, acc ->
          {node, acc}
      end)

    refs
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp collect_slot_refs(ast, source) do
    {_ast, refs} =
      Macro.prewalk(ast, [], fn
        {{:., meta, [module, :component]}, call_meta, _args} = node, acc ->
          case {module, Keyword.get(call_meta, :slots, [])} do
            {Phoenix.LiveView.TagEngine, slots} ->
              {node, slot_entries(source, slots, meta) ++ acc}

            {{:__aliases__, _, [:Phoenix, :LiveView, :TagEngine]}, slots} ->
              {node, slot_entries(source, slots, meta) ++ acc}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    refs
    |> Enum.reject(fn {slot_name, _range} -> slot_name == "inner_block" end)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp collect_local_bindings(ast, source) do
    {_ast, refs} =
      Macro.prewalk(ast, [], fn
        {:<-, meta, [lhs, _rhs]} = node, acc ->
          {node, pattern_bindings(source, lhs, meta) ++ acc}

        {:->, meta, [patterns, _body]} = node, acc when is_list(patterns) ->
          bindings =
            Enum.flat_map(patterns, fn pattern ->
              pattern_bindings(source, pattern, meta)
            end)

          {node, bindings ++ acc}

        node, acc ->
          {node, acc}
      end)

    refs
    |> Enum.reject(fn {name, _range, _line} -> name in ["_", "assigns"] end)
    |> Enum.reverse()
    |> Enum.uniq_by(fn {name, _range, line} -> {name, line} end)
  end

  defp pattern_bindings(source, pattern, fallback_meta) do
    {_pattern, bindings} =
      Macro.prewalk(pattern, [], fn
        {name, meta, context} = node, acc
        when is_atom(name) and is_atom(context) and
               name not in [:_, :assigns, :__MODULE__, :__DIR__, :__ENV__, :__CALLER__] ->
          line = Keyword.get(meta, :line, Keyword.get(fallback_meta, :line, 1))
          range = local_range(source, meta, Atom.to_string(name), line)
          {node, [{Atom.to_string(name), range, line} | acc]}

        node, acc ->
          {node, acc}
      end)

    bindings
  end

  defp slot_entries(source, slots, meta) do
    Enum.map(slots, fn slot_name ->
      name = Atom.to_string(slot_name)
      {name, slot_range(source, meta, name)}
    end)
  end

  defp component_document(relative_path, owner, symbol, display_name, range) do
    %Scip.Document{
      language: "elixir",
      relative_path: relative_path,
      occurrences: [
        %Scip.Occurrence{range: range, symbol: symbol, symbol_roles: Scip.role_read()}
      ],
      symbols: [
        %Scip.SymbolInformation{
          symbol: symbol,
          kind: Scip.kind_function(),
          display_name: display_name,
          enclosing_symbol: owner
        }
      ]
    }
  end

  defp meta_range(meta, name, source_meta \\ nil, column_offset \\ 0) do
    line = Keyword.get(meta, :line, Keyword.get(source_meta || [], :line, 1))
    column = Keyword.get(meta, :column, Keyword.get(source_meta || [], :column, 1))
    start_column = max(column - 1 + column_offset, 0)
    end_column = start_column + String.length(name) - min(column_offset, 0)
    [line - 1, start_column, end_column]
  end

  defp name_range(source, meta, name, prefix, source_meta \\ nil) do
    line = Keyword.get(meta, :line, Keyword.get(source_meta || [], :line, 1))
    fallback = meta_range(meta, name, source_meta)

    locate_on_line(source, line, prefix, fallback, fn column ->
      start_column = column + String.length(prefix) - String.length(name)
      [line - 1, start_column, start_column + String.length(name)]
    end)
  end

  defp assign_range(source, meta, name) do
    line = Keyword.get(meta, :line, 1)
    fallback = meta_range(meta, name, nil, -1)

    locate_on_line(source, line, "@#{name}", fallback, fn column ->
      [line - 1, column, column + String.length(name) + 1]
    end)
  end

  defp slot_range(source, meta, name) do
    line = Keyword.get(meta, :line, 1)
    fallback = meta_range(meta, ":#{name}")

    locate_on_line(source, line, "<:#{name}", fallback, fn column ->
      [line - 1, column + 1, column + String.length(name) + 2]
    end)
  end

  defp local_range(source, meta, name, line) do
    fallback = meta_range(meta, name)

    locate_identifier_on_line(source, line, name, fallback)
  end

  defp locate_identifier_on_line(source, line, name, fallback) do
    case line_text(source, line) do
      nil ->
        fallback

      text ->
        regex = ~r/(^|[^A-Za-z0-9_])#{Regex.escape(name)}([^A-Za-z0-9_]|$)/

        case Regex.run(regex, text, return: :index) do
          [{start, _len}, {prefix_start, prefix_len}, _suffix] ->
            column = start + prefix_start + prefix_len
            [line - 1, column, column + String.length(name)]

          _ ->
            fallback
        end
    end
  end

  defp locate_on_line(source, line, needle, fallback, builder) do
    case line_text(source, line) do
      nil ->
        fallback

      text ->
        case :binary.match(text, needle) do
          {column, _len} -> builder.(column)
          :nomatch -> fallback
        end
    end
  end

  defp line_text(source, line) when line > 0 do
    source
    |> String.split("\n")
    |> Enum.at(line - 1)
  end

  defp line_text(_source, _line), do: nil

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

  defp empty_document(relative_path) do
    %Scip.Document{language: "elixir", relative_path: relative_path}
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
    |> Enum.map(fn {_symbol, group} ->
      Enum.reduce(group, hd(group), fn sym, acc ->
        %{acc | relationships: Enum.uniq(acc.relationships ++ sym.relationships)}
      end)
    end)
  end
end
