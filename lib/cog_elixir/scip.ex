defmodule CogElixir.Scip do
  @moduledoc false

  # SCIP symbol roles (bitfield)
  @definition 0x1
  @import_role 0x2
  @write_access 0x4
  @read_access 0x8

  def role_definition, do: @definition
  def role_import, do: @import_role
  def role_write, do: @write_access
  def role_read, do: @read_access

  # SCIP symbol kinds
  @kind_constant 8
  @kind_field 15
  @kind_function 17
  @kind_interface 21
  @kind_macro 25
  @kind_module 29
  @kind_parameter 37
  @kind_type 54

  def kind_constant, do: @kind_constant
  def kind_field, do: @kind_field
  def kind_function, do: @kind_function
  def kind_interface, do: @kind_interface
  def kind_macro, do: @kind_macro
  def kind_module, do: @kind_module
  def kind_parameter, do: @kind_parameter
  def kind_type, do: @kind_type

  defmodule Index do
    @moduledoc false
    defstruct metadata: nil, documents: [], external_symbols: []
  end

  defmodule Metadata do
    @moduledoc false
    defstruct version: 0, tool_info: nil, project_root: "", text_document_encoding: 1
  end

  defmodule ToolInfo do
    @moduledoc false
    defstruct name: "", version: "", arguments: []
  end

  defmodule Document do
    @moduledoc false
    defstruct language: "elixir", relative_path: "", occurrences: [], symbols: []
  end

  defmodule Occurrence do
    @moduledoc false
    defstruct range: [],
              symbol: "",
              symbol_roles: 0,
              syntax_kind: 0,
              enclosing_range: []
  end

  defmodule SymbolInformation do
    @moduledoc false
    defstruct symbol: "",
              documentation: [],
              relationships: [],
              kind: 0,
              display_name: "",
              enclosing_symbol: ""
  end

  defmodule Relationship do
    @moduledoc false
    defstruct symbol: "",
              is_reference: false,
              is_implementation: false,
              is_type_definition: false,
              is_definition: false
  end
end
