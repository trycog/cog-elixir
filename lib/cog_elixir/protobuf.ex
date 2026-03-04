defmodule CogElixir.Protobuf do
  @moduledoc false

  import Bitwise

  alias CogElixir.Scip

  # Wire types
  @wire_varint 0
  @wire_delimited 2

  # --- Low-level encoding ---

  def encode_varint(value) when value >= 0 and value < 128, do: <<value>>

  def encode_varint(value) when value >= 0 do
    <<((value &&& 0x7F) ||| 0x80)>> <> encode_varint(value >>> 7)
  end

  def encode_varint(value) when value < 0 do
    encode_varint(value &&& 0xFFFFFFFFFFFFFFFF)
  end

  def encode_tag(field_number, wire_type) do
    encode_varint((field_number <<< 3) ||| wire_type)
  end

  # --- Field encoders ---

  def encode_string_field(_field_number, ""), do: []

  def encode_string_field(field_number, value) when is_binary(value) do
    [encode_tag(field_number, @wire_delimited), encode_varint(byte_size(value)), value]
  end

  def encode_int32_field(_field_number, 0), do: []

  def encode_int32_field(field_number, value) do
    [encode_tag(field_number, @wire_varint), encode_varint(value)]
  end

  def encode_bool_field(_field_number, false), do: []

  def encode_bool_field(field_number, true) do
    [encode_tag(field_number, @wire_varint), encode_varint(1)]
  end

  def encode_message_field(field_number, message_iodata) do
    data = IO.iodata_to_binary(message_iodata)

    if byte_size(data) == 0 do
      []
    else
      [encode_tag(field_number, @wire_delimited), encode_varint(byte_size(data)), data]
    end
  end

  def encode_packed_int32_field(_field_number, []), do: []

  def encode_packed_int32_field(field_number, values) do
    packed = IO.iodata_to_binary(Enum.map(values, &encode_varint/1))
    [encode_tag(field_number, @wire_delimited), encode_varint(byte_size(packed)), packed]
  end

  def encode_repeated_message_field(_field_number, []), do: []

  def encode_repeated_message_field(field_number, messages) do
    Enum.map(messages, fn msg_iodata ->
      data = IO.iodata_to_binary(msg_iodata)
      [encode_tag(field_number, @wire_delimited), encode_varint(byte_size(data)), data]
    end)
  end

  def encode_repeated_string_field(_field_number, []), do: []

  def encode_repeated_string_field(field_number, strings) do
    Enum.map(strings, fn s ->
      [encode_tag(field_number, @wire_delimited), encode_varint(byte_size(s)), s]
    end)
  end

  # --- SCIP message encoders ---
  # Field numbers from SCIP protobuf schema

  def encode_index(%Scip.Index{} = index) do
    IO.iodata_to_binary([
      encode_message_field(1, encode_metadata(index.metadata)),
      encode_repeated_message_field(2, Enum.map(index.documents, &encode_document/1)),
      encode_repeated_message_field(
        3,
        Enum.map(index.external_symbols, &encode_symbol_information/1)
      )
    ])
  end

  def encode_metadata(nil), do: []

  def encode_metadata(%Scip.Metadata{} = m) do
    [
      encode_int32_field(1, m.version),
      encode_message_field(2, encode_tool_info(m.tool_info)),
      encode_string_field(3, m.project_root),
      encode_int32_field(4, m.text_document_encoding)
    ]
  end

  def encode_tool_info(nil), do: []

  def encode_tool_info(%Scip.ToolInfo{} = t) do
    [
      encode_string_field(1, t.name),
      encode_string_field(2, t.version),
      encode_repeated_string_field(3, t.arguments)
    ]
  end

  def encode_document(%Scip.Document{} = d) do
    [
      encode_string_field(1, d.relative_path),
      encode_repeated_message_field(2, Enum.map(d.occurrences, &encode_occurrence/1)),
      encode_repeated_message_field(3, Enum.map(d.symbols, &encode_symbol_information/1)),
      encode_string_field(4, d.language)
    ]
  end

  def encode_occurrence(%Scip.Occurrence{} = o) do
    [
      encode_packed_int32_field(1, o.range),
      encode_string_field(2, o.symbol),
      encode_int32_field(3, o.symbol_roles),
      encode_int32_field(5, o.syntax_kind),
      encode_packed_int32_field(7, o.enclosing_range)
    ]
  end

  def encode_symbol_information(%Scip.SymbolInformation{} = s) do
    [
      encode_string_field(1, s.symbol),
      encode_repeated_string_field(3, s.documentation),
      encode_repeated_message_field(4, Enum.map(s.relationships, &encode_relationship/1)),
      encode_int32_field(5, s.kind),
      encode_string_field(6, s.display_name),
      encode_string_field(8, s.enclosing_symbol)
    ]
  end

  def encode_relationship(%Scip.Relationship{} = r) do
    [
      encode_string_field(1, r.symbol),
      encode_bool_field(2, r.is_reference),
      encode_bool_field(3, r.is_implementation),
      encode_bool_field(4, r.is_type_definition),
      encode_bool_field(5, r.is_definition)
    ]
  end
end
