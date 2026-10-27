import 'package:plc_core/plc_core.dart';
import 'package:test/test.dart';

void main() {
  group('BitAddress', () {
    test('parses with and without %', () {
      expect(BitAddress.parse('%I0.0'), const BitAddress(MemoryArea.input, 0, 0));
      expect(BitAddress.parse('q1.7'), const BitAddress(MemoryArea.output, 1, 7));
      expect(BitAddress.parse(' %M10.3 ').index, 83);
      expect(BitAddress.parse('%M10.3').toString(), '%M10.3');
    });

    test('rejects malformed addresses', () {
      for (final text in ['%I0.8', '%X0.0', '%I0', 'I.0', '%IW0', '%I0.0.0', '']) {
        expect(BitAddress.tryParse(text), isNull, reason: text);
      }
    });
  });

  group('time literals', () {
    test('parse', () {
      expect(parseTimeLiteral('T#5s'), 5000);
      expect(parseTimeLiteral('t#100ms'), 100);
      expect(parseTimeLiteral('T#1m30s'), 90000);
      expect(parseTimeLiteral('TIME#1D_2H_3M_4S_5MS'), 93784005);
      expect(parseTimeLiteral('-T#2s'), -2000);
      expect(parseTimeLiteral('T#-2s'), -2000);
      expect(parseTimeLiteral('T#24D_20H_31M_23S_647MS'), timeMax);
    });

    test('reject malformed or out of range', () {
      for (final text in ['T#', 'T#5', 'T#5x', 'T#30s1m', 'T#1s1s', '5s', 'T#24D_20H_31M_23S_648MS']) {
        expect(parseTimeLiteral(text), isNull, reason: text);
      }
    });

    test('format', () {
      expect(formatTime(0), 'T#0MS');
      expect(formatTime(90000), 'T#1M_30S');
      expect(formatTime(-1500), '-T#1S_500MS');
    });
  });

  test('INT literals respect the 16-bit range', () {
    expect(parseIntLiteral('32767'), intMax);
    expect(parseIntLiteral('-32768'), intMin);
    expect(parseIntLiteral('+7'), 7);
    expect(parseIntLiteral('32768'), isNull);
    expect(parseIntLiteral('1.5'), isNull);
  });

  test('identifiers', () {
    expect(isValidIdentifier('Siłownik_1A'), isTrue);
    expect(isValidIdentifier('_x'), isTrue);
    expect(isValidIdentifier('1A'), isFalse);
    expect(isValidIdentifier('A.B'), isFalse);
    expect(isValidIdentifier('A B'), isFalse);
    expect(isValidIdentifier('true'), isFalse);
  });
}
