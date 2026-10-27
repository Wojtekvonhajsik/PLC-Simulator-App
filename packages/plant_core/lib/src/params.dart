/// Definition of an editable element parameter. The editor builds the
/// properties panel from these definitions.
sealed class ParamDef {
  const ParamDef(this.key, this.label);

  final String key;

  /// User-facing label (Polish).
  final String label;
}

final class BoolParam extends ParamDef {
  const BoolParam(super.key, super.label, {this.defaultValue = false});

  final bool defaultValue;
}

final class NumberParam extends ParamDef {
  const NumberParam(
    super.key,
    super.label, {
    required this.defaultValue,
    required this.min,
    required this.max,
    this.unit = '',
  });

  final double defaultValue;
  final double min;
  final double max;
  final String unit;
}

final class ChoiceParam extends ParamDef {
  const ChoiceParam(super.key, super.label, {required this.options, required this.defaultValue});

  /// Value → user-facing label.
  final Map<String, String> options;
  final String defaultValue;
}

/// Parameters of an element with defaults applied and types checked.
final class ParamValues {
  const ParamValues(this._values);

  final Map<String, Object> _values;

  bool boolean(String key) => _values[key]! as bool;
  double number(String key) => _values[key]! as double;
  String choice(String key) => _values[key]! as String;

  Map<String, Object> toMap() => Map.unmodifiable(_values);
}

/// Resolves [raw] against [defs]. Invalid or missing values fall back to the
/// default; each problem is reported through [onError].
ParamValues resolveParams(List<ParamDef> defs, Map<String, Object?> raw, void Function(String message) onError) {
  final values = <String, Object>{};
  for (final def in defs) {
    final value = raw[def.key];
    switch (def) {
      case BoolParam(:final defaultValue):
        if (value == null) {
          values[def.key] = defaultValue;
        } else if (value is bool) {
          values[def.key] = value;
        } else {
          onError('Parametr „${def.label}” musi być wartością tak/nie.');
          values[def.key] = defaultValue;
        }
      case NumberParam(:final defaultValue, :final min, :final max, :final unit):
        if (value == null) {
          values[def.key] = defaultValue;
        } else if (value is num && value >= min && value <= max) {
          values[def.key] = value.toDouble();
        } else {
          onError('Parametr „${def.label}” musi być liczbą z zakresu $min…$max $unit.'.trimRight());
          values[def.key] = defaultValue;
        }
      case ChoiceParam(:final options, :final defaultValue):
        if (value == null) {
          values[def.key] = defaultValue;
        } else if (value is String && options.containsKey(value)) {
          values[def.key] = value;
        } else {
          onError('Parametr „${def.label}” ma niedozwoloną wartość „$value”.');
          values[def.key] = defaultValue;
        }
    }
  }
  for (final key in raw.keys) {
    if (!defs.any((d) => d.key == key)) onError('Nieznany parametr „$key”.');
  }
  return ParamValues(values);
}
