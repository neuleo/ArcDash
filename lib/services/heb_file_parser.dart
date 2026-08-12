import 'dart:typed_data';

class HebFile {
  static const blockAddresses = [
    0x00,
    0x06,
    0x0C,
    0x12,
    0x18,
    0x1E,
    0x24,
    0x2A,
    0x30,
    0x63,
    0x69,
    0x7C,
    0x82,
    0x88,
    0x8E,
    0x94,
    0x9A,
    0xA0,
    0xA6,
    0xAC,
    0xB2,
    0xB8,
    0xBE,
    0xC4,
    0xCA,
    0xD0,
  ];
  static const expectedLength = 696;
  static const blockLength = 12;
  static const canConfigLength = 384; // 696 - (26 * 12) = 384

  final List<int> bytes;
  final Map<int, List<int>> blocks;

  const HebFile._({required this.bytes, required this.blocks});

  factory HebFile.parse(List<int> input) {
    if (input.length != expectedLength) {
      throw FormatException(
          'HEB must contain $expectedLength bytes, got ${input.length}');
    }
    final bytes = List<int>.unmodifiable(input);
    final blocks = <int, List<int>>{};
    for (var index = 0; index < blockAddresses.length; index++) {
      final start = index * blockLength;
      blocks[blockAddresses[index]] =
          List.unmodifiable(bytes.sublist(start, start + blockLength));
    }
    return HebFile._(
      bytes: bytes,
      blocks: Map.unmodifiable(blocks),
    );
  }

  factory HebFile.fromBlocks(Map<int, List<int>> blocksMap,
      [List<int>? canConfig]) {
    final buffer = List<int>.filled(expectedLength, 0);
    for (var index = 0; index < blockAddresses.length; index++) {
      final addr = blockAddresses[index];
      final blockData = blocksMap[addr] ?? List<int>.filled(blockLength, 0);
      final start = index * blockLength;
      for (var b = 0; b < blockLength && b < blockData.length; b++) {
        buffer[start + b] = blockData[b];
      }
    }
    final canStart = blockAddresses.length * blockLength;
    if (canConfig != null) {
      for (var c = 0; c < canConfigLength && c < canConfig.length; c++) {
        buffer[canStart + c] = canConfig[c];
      }
    }
    return HebFile.parse(buffer);
  }

  List<int> block(int address) {
    final value = blocks[address];
    if (value == null) throw ArgumentError.value(address, 'address');
    return value;
  }

  List<int> get canConfiguration =>
      List.unmodifiable(bytes.sublist(blockAddresses.length * blockLength));

  Uint8List toBytes() => Uint8List.fromList(bytes);
}
