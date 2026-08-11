import 'package:flutter/services.dart' show rootBundle;
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/protocol_service.dart';

/// Asset path of the verified factory baseline (Phase 15, T092).
const String stockBasemapAssetPath = 'assets/basemaps/unmodified_basemap.heb';

/// A single 16-bit factory register value to be written back to the controller.
class HebRestoreWrite {
  final int address;
  final int value;

  const HebRestoreWrite({required this.address, required this.value});

  List<int> toPacket() => ProtocolService.buildWritePacket(address, value);

  @override
  String toString() =>
      '0x${address.toRadixString(16).padLeft(2, '0')} '
      '= 0x${value.toRadixString(16).padLeft(4, '0')}';
}

/// Serialized factory write sequence produced from an HEB file.
class StockRestorePlan {
  final List<HebRestoreWrite> writes;

  const StockRestorePlan(this.writes);

  bool get isEmpty => writes.isEmpty;
}

/// Turns `unmodified_basemap.heb` into the atomic write sequence that restores
/// the factory baseline. Every 12-byte block is expanded into six 16-bit
/// register writes (register address = block address + word index), matching
/// how the controller maps the parameter memory (maxSpeed at 0x15 in the 0x12
/// block, maxLineCurrent at 0x19 in the 0x18 block).
class StockHebRestorePlanner {
  const StockHebRestorePlanner();

  StockRestorePlan plan(HebFile heb) {
    final writes = <HebRestoreWrite>[];
    for (final blockAddress in HebFile.blockAddresses) {
      final block = heb.block(blockAddress);
      for (var byte = 0; byte + 1 < block.length; byte += 2) {
        final value = block[byte] | (block[byte + 1] << 8);
        writes.add(HebRestoreWrite(
          address: blockAddress + byte ~/ 2,
          value: value,
        ));
      }
    }
    return StockRestorePlan(List.unmodifiable(writes));
  }

  /// Loads and parses the bundled factory basemap asset.
  Future<HebFile> loadFromAsset({
    String assetPath = stockBasemapAssetPath,
  }) async {
    final data = await rootBundle.load(assetPath);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return HebFile.parse(bytes);
  }
}