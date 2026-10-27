/// Memory areas addressable by bit operands.
enum MemoryArea {
  input('I'),
  output('Q'),
  marker('M');

  const MemoryArea(this.prefix);

  final String prefix;
}

/// Absolute bit address such as `%I0.0`, `%Q1.7` or `%M10.3`.
final class BitAddress {
  const BitAddress(this.area, this.byte, this.bit)
      : assert(byte >= 0),
        assert(bit >= 0 && bit <= 7);

  final MemoryArea area;
  final int byte;
  final int bit;

  static final _pattern = RegExp(r'^%?([IQM])(\d{1,5})\.(\d)$', caseSensitive: false);

  /// Parses `%I0.0` (the `%` is optional). Returns null for malformed text.
  static BitAddress? tryParse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    final area = switch (match[1]!.toUpperCase()) {
      'I' => MemoryArea.input,
      'Q' => MemoryArea.output,
      _ => MemoryArea.marker,
    };
    final bit = int.parse(match[3]!);
    if (bit > 7) return null;
    return BitAddress(area, int.parse(match[2]!), bit);
  }

  static BitAddress parse(String text) => tryParse(text) ?? (throw FormatException('Invalid bit address', text));

  /// Linear bit index inside the area.
  int get index => byte * 8 + bit;

  @override
  bool operator ==(Object other) => other is BitAddress && other.area == area && other.byte == byte && other.bit == bit;

  @override
  int get hashCode => Object.hash(area, byte, bit);

  @override
  String toString() => '%${area.prefix}$byte.$bit';
}
