defmodule CogElixir.Analyzer do
  @moduledoc false

  alias CogElixir.Scip
  alias CogElixir.Symbol

  defstruct source: "",
            package_name: "",
            relative_path: "",
            occurrences: [],
            symbols: [],
            scope_stack: [],
            local_counter: 0,
            pending_doc: nil,
            seen_functions: MapSet.new()

  def analyze(source, package_name, relative_path) do
    opts = [columns: true, token_metadata: true]

    case Code.string_to_quoted(source, opts) do
      {:ok, ast} ->
        state = %__MODULE__{
          source: source,
          package_name: package_name,
          relative_path: relative_path
        }

        state = walk(ast, state)

        %Scip.Document{
          language: "elixir",
          relative_path: relative_path,
          occurrences: Enum.reverse(state.occurrences),
          symbols: Enum.reverse(state.symbols)
        }

      {:error, _} ->
        %Scip.Document{language: "elixir", relative_path: relative_path}
    end
  end

  # --- AST Walking ---

  # Block of expressions
  defp walk({:__block__, _meta, exprs}, state) when is_list(exprs) do
    Enum.reduce(exprs, state, &walk/2)
  end

  # defmodule
  defp walk({:defmodule, _meta, [alias_node, [do: body]]}, state) do
    module_name = extract_module_name(alias_node, state)
    symbol = Symbol.module_symbol(state.package_name, module_name)
    range = alias_range(alias_node, module_name)

    {doc, state} = pop_pending_doc(state)

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_module(),
      display_name: module_name,
      documentation: doc_list(doc),
      enclosing_symbol: current_enclosing(state)
    }

    state =
      state
      |> add_occurrence(occurrence)
      |> add_symbol_info(sym_info)
      |> push_scope(symbol)

    state = walk(body, state)
    pop_scope(state)
  end

  # defmodule without do block (shouldn't happen normally, but guard)
  defp walk({:defmodule, _meta, _}, state), do: state

  # defprotocol
  defp walk({:defprotocol, _meta, [alias_node, [do: body]]}, state) do
    module_name = extract_module_name(alias_node, state)
    symbol = Symbol.module_symbol(state.package_name, module_name)
    range = alias_range(alias_node, module_name)

    {doc, state} = pop_pending_doc(state)

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_interface(),
      display_name: module_name,
      documentation: doc_list(doc),
      enclosing_symbol: current_enclosing(state)
    }

    state =
      state
      |> add_occurrence(occurrence)
      |> add_symbol_info(sym_info)
      |> push_scope(symbol)

    state = walk(body, state)
    pop_scope(state)
  end

  defp walk({:defprotocol, _meta, _}, state), do: state

  # defimpl Protocol, for: Type, do: body (3 args: protocol, [for: type], [do: body])
  defp walk({:defimpl, _meta, [protocol_node, for_opts, [do: body]]}, state)
       when is_list(for_opts) do
    protocol_name = extract_module_name(protocol_node, state)
    for_type = Keyword.get(for_opts, :for)

    impl_name =
      if for_type do
        type_name = extract_module_name(for_type, state)
        "#{protocol_name}.#{type_name}"
      else
        protocol_name
      end

    symbol = Symbol.module_symbol(state.package_name, impl_name)
    range = alias_range(protocol_node, protocol_name)

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_module(),
      display_name: impl_name,
      enclosing_symbol: current_enclosing(state)
    }

    state =
      state
      |> add_occurrence(occurrence)
      |> add_symbol_info(sym_info)
      |> push_scope(symbol)

    state = walk(body, state)
    pop_scope(state)
  end

  # defimpl with 2 args (protocol, [for: type, do: body])
  defp walk({:defimpl, _meta, [protocol_node, opts]}, state) when is_list(opts) do
    body = Keyword.get(opts, :do)
    for_type = Keyword.get(opts, :for)
    protocol_name = extract_module_name(protocol_node, state)

    impl_name =
      if for_type do
        type_name = extract_module_name(for_type, state)
        "#{protocol_name}.#{type_name}"
      else
        protocol_name
      end

    symbol = Symbol.module_symbol(state.package_name, impl_name)
    range = alias_range(protocol_node, protocol_name)

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_module(),
      display_name: impl_name,
      enclosing_symbol: current_enclosing(state)
    }

    state =
      state
      |> add_occurrence(occurrence)
      |> add_symbol_info(sym_info)
      |> push_scope(symbol)

    state = if body, do: walk(body, state), else: state
    pop_scope(state)
  end

  defp walk({:defimpl, _meta, _}, state), do: state

  # def / defp
  defp walk({def_type, meta, [head | _rest]} = node, state)
       when def_type in [:def, :defp] do
    {func_name, func_meta, args} = extract_func_head(head)
    arity = if is_list(args), do: length(args), else: 0
    module_name = current_module_name(state)
    symbol = Symbol.function_symbol(state.package_name, module_name, func_name, arity)

    line = Keyword.get(func_meta, :line, Keyword.get(meta, :line, 1))
    col = Keyword.get(func_meta, :column, Keyword.get(meta, :column, 1))
    name_str = Atom.to_string(func_name)
    range = [line - 1, col - 1, col - 1 + String.length(name_str)]

    func_key = {func_name, arity}
    already_seen = MapSet.member?(state.seen_functions, func_key)

    {doc, state} = pop_pending_doc(state)

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    state = add_occurrence(state, occurrence)

    state =
      if already_seen do
        state
      else
        sym_info = %Scip.SymbolInformation{
          symbol: symbol,
          kind: Scip.kind_function(),
          display_name: "#{name_str}/#{arity}",
          documentation: doc_list(doc),
          enclosing_symbol: current_enclosing(state)
        }

        state
        |> add_symbol_info(sym_info)
        |> mark_function_seen(func_key)
      end

    # Process parameters
    state = push_scope(state, symbol)
    state = if is_list(args), do: walk_params(args, state), else: state
    state = walk_function_body(node, state)
    pop_scope(state)
  end

  # defmacro / defmacrop
  defp walk({def_type, meta, [head | _rest]} = node, state)
       when def_type in [:defmacro, :defmacrop] do
    {func_name, func_meta, args} = extract_func_head(head)
    arity = if is_list(args), do: length(args), else: 0
    module_name = current_module_name(state)
    symbol = Symbol.macro_symbol(state.package_name, module_name, func_name, arity)

    line = Keyword.get(func_meta, :line, Keyword.get(meta, :line, 1))
    col = Keyword.get(func_meta, :column, Keyword.get(meta, :column, 1))
    name_str = Atom.to_string(func_name)
    range = [line - 1, col - 1, col - 1 + String.length(name_str)]

    {doc, state} = pop_pending_doc(state)

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_macro(),
      display_name: "#{name_str}/#{arity}",
      documentation: doc_list(doc),
      enclosing_symbol: current_enclosing(state)
    }

    state =
      state
      |> add_occurrence(occurrence)
      |> add_symbol_info(sym_info)
      |> push_scope(symbol)

    state = if is_list(args), do: walk_params(args, state), else: state
    state = walk_function_body(node, state)
    pop_scope(state)
  end

  # defguard / defguardp
  defp walk({def_type, meta, [head | _rest]} = node, state)
       when def_type in [:defguard, :defguardp] do
    {func_name, func_meta, args} = extract_func_head(head)
    arity = if is_list(args), do: length(args), else: 0
    module_name = current_module_name(state)
    symbol = Symbol.macro_symbol(state.package_name, module_name, func_name, arity)

    line = Keyword.get(func_meta, :line, Keyword.get(meta, :line, 1))
    col = Keyword.get(func_meta, :column, Keyword.get(meta, :column, 1))
    name_str = Atom.to_string(func_name)
    range = [line - 1, col - 1, col - 1 + String.length(name_str)]

    {doc, state} = pop_pending_doc(state)

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_macro(),
      display_name: "#{name_str}/#{arity}",
      documentation: doc_list(doc),
      enclosing_symbol: current_enclosing(state)
    }

    state =
      state
      |> add_occurrence(occurrence)
      |> add_symbol_info(sym_info)
      |> push_scope(symbol)

    state = if is_list(args), do: walk_params(args, state), else: state
    state = walk_function_body(node, state)
    pop_scope(state)
  end

  # defdelegate
  defp walk({:defdelegate, meta, [{func_name, func_meta, args} | _opts]}, state)
       when is_atom(func_name) and is_list(args) do
    arity = length(args)
    module_name = current_module_name(state)
    symbol = Symbol.function_symbol(state.package_name, module_name, func_name, arity)

    line = Keyword.get(func_meta, :line, Keyword.get(meta, :line, 1))
    col = Keyword.get(func_meta, :column, Keyword.get(meta, :column, 1))
    name_str = Atom.to_string(func_name)
    range = [line - 1, col - 1, col - 1 + String.length(name_str)]

    {doc, state} = pop_pending_doc(state)

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_function(),
      display_name: "#{name_str}/#{arity}",
      documentation: doc_list(doc),
      enclosing_symbol: current_enclosing(state)
    }

    state
    |> add_occurrence(occurrence)
    |> add_symbol_info(sym_info)
  end

  defp walk({:defdelegate, _meta, _}, state), do: state

  # defstruct
  defp walk({:defstruct, meta, [fields]}, state) when is_list(fields) do
    module_name = current_module_name(state)
    line = Keyword.get(meta, :line, 1) - 1
    col = Keyword.get(meta, :column, 1) - 1

    Enum.reduce(fields, state, fn
      {field_name, _default}, acc when is_atom(field_name) ->
        symbol = Symbol.field_symbol(state.package_name, module_name, field_name)

        occurrence = %Scip.Occurrence{
          range: [line, col, col + String.length("defstruct")],
          symbol: symbol,
          symbol_roles: Scip.role_definition()
        }

        sym_info = %Scip.SymbolInformation{
          symbol: symbol,
          kind: Scip.kind_field(),
          display_name: Atom.to_string(field_name),
          enclosing_symbol: current_enclosing(acc)
        }

        acc
        |> add_occurrence(occurrence)
        |> add_symbol_info(sym_info)

      field_name, acc when is_atom(field_name) ->
        symbol = Symbol.field_symbol(state.package_name, module_name, field_name)

        occurrence = %Scip.Occurrence{
          range: [line, col, col + String.length("defstruct")],
          symbol: symbol,
          symbol_roles: Scip.role_definition()
        }

        sym_info = %Scip.SymbolInformation{
          symbol: symbol,
          kind: Scip.kind_field(),
          display_name: Atom.to_string(field_name),
          enclosing_symbol: current_enclosing(acc)
        }

        acc
        |> add_occurrence(occurrence)
        |> add_symbol_info(sym_info)

      _, acc ->
        acc
    end)
  end

  defp walk({:defstruct, _meta, _}, state), do: state

  # @moduledoc / @doc
  defp walk({:@, _meta, [{doc_type, _attr_meta, [doc_string]}]}, state)
       when doc_type in [:doc, :moduledoc] and is_binary(doc_string) do
    %{state | pending_doc: doc_string}
  end

  defp walk({:@, _meta, [{doc_type, _attr_meta, [false]}]}, state)
       when doc_type in [:doc, :moduledoc] do
    %{state | pending_doc: nil}
  end

  # @type / @typep / @opaque
  defp walk({:@, meta, [{type_kind, _attr_meta, [{:"::", _, [type_head | _]}]}]}, state)
       when type_kind in [:type, :typep, :opaque] do
    {type_name, type_meta, type_args} = extract_type_head(type_head)
    arity = if is_list(type_args), do: length(type_args), else: 0
    module_name = current_module_name(state)
    symbol = Symbol.type_symbol(state.package_name, module_name, type_name, arity)

    line = Keyword.get(type_meta, :line, Keyword.get(meta, :line, 1))
    col = Keyword.get(type_meta, :column, Keyword.get(meta, :column, 1))
    name_str = Atom.to_string(type_name)
    range = [line - 1, col - 1, col - 1 + String.length(name_str)]

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_type(),
      display_name: "#{name_str}/#{arity}",
      enclosing_symbol: current_enclosing(state)
    }

    state
    |> add_occurrence(occurrence)
    |> add_symbol_info(sym_info)
  end

  # @type without :: (type alias like @type t)
  defp walk({:@, meta, [{type_kind, _attr_meta, [{type_name, type_meta, _}]}]}, state)
       when type_kind in [:type, :typep, :opaque] and is_atom(type_name) do
    module_name = current_module_name(state)
    symbol = Symbol.type_symbol(state.package_name, module_name, type_name, 0)

    line = Keyword.get(type_meta, :line, Keyword.get(meta, :line, 1))
    col = Keyword.get(type_meta, :column, Keyword.get(meta, :column, 1))
    name_str = Atom.to_string(type_name)
    range = [line - 1, col - 1, col - 1 + String.length(name_str)]

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_type(),
      display_name: "#{name_str}/0",
      enclosing_symbol: current_enclosing(state)
    }

    state
    |> add_occurrence(occurrence)
    |> add_symbol_info(sym_info)
  end

  # @callback / @macrocallback
  defp walk({:@, meta, [{cb_type, _attr_meta, [{:"::", _, [cb_head | _]}]}]}, state)
       when cb_type in [:callback, :macrocallback] do
    {cb_name, cb_meta, cb_args} = extract_type_head(cb_head)
    arity = if is_list(cb_args), do: length(cb_args), else: 0
    module_name = current_module_name(state)
    symbol = Symbol.callback_symbol(state.package_name, module_name, cb_name, arity)

    line = Keyword.get(cb_meta, :line, Keyword.get(meta, :line, 1))
    col = Keyword.get(cb_meta, :column, Keyword.get(meta, :column, 1))
    name_str = Atom.to_string(cb_name)
    range = [line - 1, col - 1, col - 1 + String.length(name_str)]

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_function(),
      display_name: "#{name_str}/#{arity}",
      enclosing_symbol: current_enclosing(state)
    }

    state
    |> add_occurrence(occurrence)
    |> add_symbol_info(sym_info)
  end

  # @behaviour Module
  defp walk({:@, meta, [{:behaviour, _attr_meta, [module_ref]}]}, state) do
    module_name = extract_module_name(module_ref, state)
    range = alias_range(module_ref, module_name)

    # If we can't get a real range from the alias, use @behaviour position
    range =
      if range == [0, 0, 0] do
        line = Keyword.get(meta, :line, 1)
        [line - 1, 0, String.length(module_name)]
      else
        range
      end

    symbol = Symbol.module_symbol(state.package_name, module_name)

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_import()
    }

    add_occurrence(state, occurrence)
  end

  # @spec - skip for now (doesn't define new symbols)
  defp walk({:@, _meta, [{:spec, _attr_meta, _}]}, state), do: state

  # @attr value (general module attribute)
  defp walk({:@, meta, [{attr_name, attr_meta, [_value]}]}, state)
       when is_atom(attr_name) and
              attr_name not in [
                :doc,
                :moduledoc,
                :type,
                :typep,
                :opaque,
                :spec,
                :callback,
                :macrocallback,
                :behaviour,
                :impl,
                :derive,
                :enforce_keys,
                :before_compile,
                :after_compile,
                :on_definition,
                :compile,
                :dialyzer,
                :external_resource,
                :on_load,
                :vsn,
                :deprecated
              ] do
    module_name = current_module_name(state)
    symbol = Symbol.attribute_symbol(state.package_name, module_name, attr_name)

    line = Keyword.get(attr_meta, :line, Keyword.get(meta, :line, 1))
    col = Keyword.get(attr_meta, :column, Keyword.get(meta, :column, 1))
    name_str = Atom.to_string(attr_name)
    range = [line - 1, col - 1, col - 1 + String.length(name_str)]

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_constant(),
      display_name: "@#{name_str}",
      enclosing_symbol: current_enclosing(state)
    }

    state
    |> add_occurrence(occurrence)
    |> add_symbol_info(sym_info)
  end

  # @attr (read without value) — skip
  defp walk({:@, _meta, [{_attr_name, _attr_meta, _}]}, state), do: state

  # alias / import / use / require
  defp walk({directive, _meta, [{:__aliases__, _alias_meta, _segments} = alias_node]}, state)
       when directive in [:alias, :import, :use, :require] do
    module_name = extract_module_name(alias_node, state)
    symbol = Symbol.module_symbol(state.package_name, module_name)
    range = alias_range(alias_node, module_name)

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_import()
    }

    add_occurrence(state, occurrence)
  end

  # alias/import/use/require with options (e.g., alias Foo, as: Bar)
  defp walk(
         {directive, _meta,
          [{:__aliases__, _alias_meta, _segments} = alias_node, _opts]},
         state
       )
       when directive in [:alias, :import, :use, :require] do
    module_name = extract_module_name(alias_node, state)
    symbol = Symbol.module_symbol(state.package_name, module_name)
    range = alias_range(alias_node, module_name)

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_import()
    }

    add_occurrence(state, occurrence)
  end

  # use with atom module (e.g., use :logger)
  defp walk({directive, _meta, _args}, state)
       when directive in [:alias, :import, :use, :require] do
    state
  end

  # Catch-all: walk children of any tuple AST node
  defp walk({_form, _meta, args}, state) when is_list(args) do
    Enum.reduce(args, state, fn arg, acc -> walk(arg, acc) end)
  end

  # Lists
  defp walk(list, state) when is_list(list) do
    Enum.reduce(list, state, fn
      {key, value}, acc when is_atom(key) ->
        walk(value, acc)

      item, acc ->
        walk(item, acc)
    end)
  end

  # Everything else (atoms, numbers, strings, etc.)
  defp walk(_other, state), do: state

  # --- Helper functions ---

  defp extract_func_head({:when, _meta, [head | _guards]}), do: extract_func_head(head)
  defp extract_func_head({name, meta, args}) when is_atom(name), do: {name, meta, args}
  defp extract_func_head(other), do: {:unknown, [], other}

  defp extract_type_head({name, meta, args}) when is_atom(name), do: {name, meta, args}
  defp extract_type_head(_), do: {:unknown, [], []}

  defp walk_function_body({_def_type, _meta, [_head]}, state), do: state

  defp walk_function_body({_def_type, _meta, [_head, [do: body]]}, state) do
    walk(body, state)
  end

  defp walk_function_body({_def_type, _meta, [_head, body]}, state) when is_list(body) do
    case Keyword.fetch(body, :do) do
      {:ok, do_body} -> walk(do_body, state)
      :error -> state
    end
  end

  defp walk_function_body(_, state), do: state

  defp walk_params(args, state) do
    Enum.reduce(args, state, fn arg, acc ->
      walk_param(arg, acc)
    end)
  end

  defp walk_param({:=, _meta, [left, right]}, state) do
    state = walk_param(left, state)
    walk_param(right, state)
  end

  defp walk_param({:\\, _meta, [param, _default]}, state) do
    walk_param(param, state)
  end

  defp walk_param({name, meta, context}, state)
       when is_atom(name) and is_atom(context) and
              name not in [:_, :__MODULE__, :__DIR__, :__ENV__, :__CALLER__] do
    symbol = Symbol.local_symbol(state.local_counter)

    line = Keyword.get(meta, :line, 1)
    col = Keyword.get(meta, :column, 1)
    name_str = Atom.to_string(name)
    range = [line - 1, col - 1, col - 1 + String.length(name_str)]

    occurrence = %Scip.Occurrence{
      range: range,
      symbol: symbol,
      symbol_roles: Scip.role_definition()
    }

    sym_info = %Scip.SymbolInformation{
      symbol: symbol,
      kind: Scip.kind_parameter(),
      display_name: name_str,
      enclosing_symbol: current_enclosing(state)
    }

    state
    |> add_occurrence(occurrence)
    |> add_symbol_info(sym_info)
    |> increment_local_counter()
  end

  # Destructured patterns — walk into them
  defp walk_param({:{}, _meta, elements}, state) when is_list(elements) do
    Enum.reduce(elements, state, &walk_param/2)
  end

  defp walk_param({_key, value}, state) do
    walk_param(value, state)
  end

  defp walk_param({:%{}, _meta, pairs}, state) when is_list(pairs) do
    Enum.reduce(pairs, state, fn
      {_k, v}, acc -> walk_param(v, acc)
      _, acc -> acc
    end)
  end

  defp walk_param(_, state), do: state

  defp extract_module_name({:__aliases__, _meta, segments}, _state) do
    segments
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(".")
  end

  defp extract_module_name(atom, _state) when is_atom(atom) do
    Atom.to_string(atom)
  end

  defp extract_module_name(_, _state), do: "Unknown"

  defp alias_range({:__aliases__, meta, segments}, module_name) do
    line = Keyword.get(meta, :line, 1)
    col = Keyword.get(meta, :column, 1)

    # For multi-segment aliases, last might have position info
    name_length =
      case Keyword.get(meta, :last, nil) do
        %{line: _, column: last_col} ->
          last_segment = List.last(segments)
          last_col - col + String.length(Atom.to_string(last_segment))

        _ ->
          String.length(module_name)
      end

    [line - 1, col - 1, col - 1 + name_length]
  end

  defp alias_range(_, _), do: [0, 0, 0]

  defp current_module_name(%__MODULE__{scope_stack: []}), do: "Unknown"

  defp current_module_name(%__MODULE__{scope_stack: [current | _]}) do
    # Extract module name from symbol string
    # Symbol format: "file . <package> unversioned <Module>#..."
    case String.split(current, " unversioned ") do
      [_, rest] ->
        case String.split(rest, "#", parts: 2) do
          [name | _] -> unescape_identifier(name)
          _ -> "Unknown"
        end

      _ ->
        "Unknown"
    end
  end

  defp current_enclosing(%__MODULE__{scope_stack: []}), do: ""
  defp current_enclosing(%__MODULE__{scope_stack: [current | _]}), do: current

  defp push_scope(state, symbol) do
    %{state | scope_stack: [symbol | state.scope_stack]}
  end

  defp pop_scope(%__MODULE__{scope_stack: []} = state), do: state
  defp pop_scope(%__MODULE__{scope_stack: [_ | rest]} = state), do: %{state | scope_stack: rest}

  defp pop_pending_doc(%__MODULE__{pending_doc: nil} = state), do: {nil, state}

  defp pop_pending_doc(%__MODULE__{pending_doc: doc} = state) do
    {doc, %{state | pending_doc: nil}}
  end

  defp doc_list(nil), do: []
  defp doc_list(doc), do: [doc]

  defp add_occurrence(state, occurrence) do
    %{state | occurrences: [occurrence | state.occurrences]}
  end

  defp add_symbol_info(state, sym_info) do
    %{state | symbols: [sym_info | state.symbols]}
  end

  defp mark_function_seen(state, func_key) do
    %{state | seen_functions: MapSet.put(state.seen_functions, func_key)}
  end

  defp increment_local_counter(state) do
    %{state | local_counter: state.local_counter + 1}
  end

  defp unescape_identifier("`" <> rest) do
    rest
    |> String.trim_trailing("`")
    |> String.replace("``", "`")
  end

  defp unescape_identifier(name), do: name
end
