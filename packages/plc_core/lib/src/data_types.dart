/// Data types visible to the user. INT and TIME exist only for counter values,
/// timer values and constants used by comparators — there is no arithmetic.
enum DataType {
  boolean('BOOL'),
  integer('INT'),
  time('TIME');

  const DataType(this.label);

  final String label;
}

const int intMin = -32768;
const int intMax = 32767;
const int timeMin = -2147483648;
const int timeMax = 2147483647;

final _identifier = RegExp(r'^[\p{L}_][\p{L}\p{N}_]*$', unicode: true);
const _reservedWords = {'TRUE', 'FALSE'};

/// Valid tag or instance name: letters, digits and `_`, not starting with a digit.
bool isValidIdentifier(String name) => _identifier.hasMatch(name) && !_reservedWords.contains(name.toUpperCase());

final _intLiteral = RegExp(r'^[+-]?\d+$');

bool looksLikeIntLiteral(String text) => _intLiteral.hasMatch(text);

/// Parses an INT constant. Returns null when malformed or out of range.
int? parseIntLiteral(String text) {
  if (!looksLikeIntLiteral(text)) return null;
  final value = int.tryParse(text);
  if (value == null || value < intMin || value > intMax) return null;
  return value;
}

final _timePrefix = RegExp(r'^(T|TIME)#', caseSensitive: false);
final _timeComponent = RegExp(r'(\d+)(MS|D|H|M|S)', caseSensitive: false);
const _unitMs = {'D': 86400000, 'H': 3600000, 'M': 60000, 'S': 1000, 'MS': 1};
const _unitOrder = ['D', 'H', 'M', 'S', 'MS'];

bool looksLikeTimeLiteral(String text) => _timePrefix.hasMatch(text);

/// Parses an IEC time literal such as `T#5s`, `T#1m30s`, `T#1D_2H_3M_4S_5MS`
/// or `-T#2s` into milliseconds. Units must appear in descending order.
int? parseTimeLiteral(String text) {
  var rest = text.trim();
  var negative = false;
  if (rest.startsWith('-')) {
    negative = true;
    rest = rest.substring(1);
  }
  final prefix = _timePrefix.firstMatch(rest);
  if (prefix == null) return null;
  rest = rest.substring(prefix.end).replaceAll('_', '');
  if (rest.startsWith('-')) {
    if (negative) return null;
    negative = true;
    rest = rest.substring(1);
  }
  if (rest.isEmpty) return null;

  var total = 0;
  var position = 0;
  var lastUnit = -1;
  for (final match in _timeComponent.allMatches(rest)) {
    if (match.start != position) return null;
    final unit = match[2]!.toUpperCase();
    final order = _unitOrder.indexOf(unit);
    if (order <= lastUnit) return null;
    lastUnit = order;
    total += int.parse(match[1]!) * _unitMs[unit]!;
    if (total > timeMax + 1) return null;
    position = match.end;
  }
  if (position != rest.length) return null;
  final value = negative ? -total : total;
  if (value < timeMin || value > timeMax) return null;
  return value;
}

/// Formats milliseconds as an IEC time literal, e.g. `T#1M_30S`.
String formatTime(int ms) {
  if (ms == 0) return 'T#0MS';
  final sign = ms < 0 ? '-' : '';
  var rest = ms.abs();
  final parts = <String>[];
  for (final unit in _unitOrder) {
    final size = _unitMs[unit]!;
    if (rest >= size) {
      parts.add('${rest ~/ size}$unit');
      rest %= size;
    }
  }
  return '${sign}T#${parts.join('_')}';
}
