defmodule CogElixir.ProtobufTest do
  use ExUnit.Case, async: true

  alias CogElixir.Protobuf
  alias CogElixir.Scip

  test "encode_varint encodes small values" do
    assert Protobuf.encode_varint(0) == <<0>>
    assert Protobuf.encode_varint(1) == <<1>>
    assert Protobuf.encode_varint(127) == <<127>>
  end

  test "encode_varint encodes multi-byte values" do
    assert Protobuf.encode_varint(128) == <<128, 1>>
    assert Protobuf.encode_varint(300) == <<172, 2>>
  end

  test "encode_varint encodes negative values as 10-byte unsigned" do
    encoded = Protobuf.encode_varint(-1)
    assert byte_size(encoded) == 10
    # -1 in two's complement u64 = all 1s
    assert encoded == <<255, 255, 255, 255, 255, 255, 255, 255, 255, 1>>
  end

  test "encode_tag produces correct bytes" do
    # field 1, wire type 0 (varint) = (1 << 3) | 0 = 8
    assert Protobuf.encode_tag(1, 0) == <<8>>
    # field 1, wire type 2 (delimited) = (1 << 3) | 2 = 10
    assert Protobuf.encode_tag(1, 2) == <<10>>
    # field 2, wire type 0 = (2 << 3) | 0 = 16
    assert Protobuf.encode_tag(2, 0) == <<16>>
  end

  test "encode_string_field skips empty strings" do
    assert Protobuf.encode_string_field(1, "") == []
  end

  test "encode_string_field encodes non-empty strings" do
    result = IO.iodata_to_binary(Protobuf.encode_string_field(1, "hello"))
    # tag(1, delimited) = 10, length=5, "hello"
    assert result == <<10, 5, "hello">>
  end

  test "encode_int32_field skips zero" do
    assert Protobuf.encode_int32_field(1, 0) == []
  end

  test "encode_int32_field encodes non-zero" do
    result = IO.iodata_to_binary(Protobuf.encode_int32_field(1, 42))
    assert result == <<8, 42>>
  end

  test "encode_packed_int32_field encodes range" do
    result = IO.iodata_to_binary(Protobuf.encode_packed_int32_field(1, [0, 4, 13]))
    # tag(1, delimited) = 10, length=3, varint(0), varint(4), varint(13)
    assert result == <<10, 3, 0, 4, 13>>
  end

  test "encode_index produces valid binary" do
    index = %Scip.Index{
      metadata: %Scip.Metadata{
        version: 0,
        tool_info: %Scip.ToolInfo{name: "cog-elixir", version: "0.1.0", arguments: []},
        project_root: "file:///tmp/test",
        text_document_encoding: 1
      },
      documents: [
        %Scip.Document{
          language: "elixir",
          relative_path: "lib/test.ex",
          occurrences: [
            %Scip.Occurrence{
              range: [0, 11, 17],
              symbol: "file . test unversioned Simple#",
              symbol_roles: 1
            }
          ],
          symbols: [
            %Scip.SymbolInformation{
              symbol: "file . test unversioned Simple#",
              kind: 29,
              display_name: "Simple"
            }
          ]
        }
      ],
      external_symbols: []
    }

    data = Protobuf.encode_index(index)
    assert is_binary(data)
    assert byte_size(data) > 0
  end
end
