import 'address.dart';

/// Size of the addressable memory areas.
final class PlcConfig {
  const PlcConfig({this.inputBytes = 16, this.outputBytes = 16, this.markerBytes = 256});

  final int inputBytes;
  final int outputBytes;
  final int markerBytes;

  int bytesOf(MemoryArea area) => switch (area) {
        MemoryArea.input => inputBytes,
        MemoryArea.output => outputBytes,
        MemoryArea.marker => markerBytes,
      };

  bool contains(BitAddress address) => address.byte < bytesOf(address.area);
}

/// Process image of inputs (PII), process image of outputs (PIQ) and bit memory (M).
final class ProcessMemory {
  ProcessMemory(PlcConfig config)
      : inputs = List.filled(config.inputBytes * 8, false),
        outputs = List.filled(config.outputBytes * 8, false),
        markers = List.filled(config.markerBytes * 8, false);

  final List<bool> inputs;
  final List<bool> outputs;
  final List<bool> markers;

  List<bool> area(MemoryArea area) => switch (area) {
        MemoryArea.input => inputs,
        MemoryArea.output => outputs,
        MemoryArea.marker => markers,
      };

  bool read(BitAddress address) => area(address.area)[address.index];

  void write(BitAddress address, bool value) => area(address.area)[address.index] = value;
}
