import 'package:plant_core/plant_core.dart';
import 'package:plc_core/plc_core.dart';

enum IoDiagnosticCode {
  invalidAddress,
  unknownTag,
  wrongArea,
  addressOutOfRange,
  inputConflict,
}

/// Problem with a plant signal ↔ PLC address binding. [message] is user-facing (Polish).
final class IoDiagnostic {
  const IoDiagnostic(this.severity, this.code, this.message, {required this.elementId, required this.signal});

  final Severity severity;
  final IoDiagnosticCode code;
  final String message;
  final String elementId;
  final String signal;

  bool get isError => severity == Severity.error;

  @override
  String toString() => '${severity.name} ${code.name}: $message (element=$elementId signal=$signal)';
}

/// Plant signal bound to a resolved PLC bit address.
final class ResolvedBinding {
  const ResolvedBinding(this.elementId, this.signal, this.address);

  final String elementId;
  final String signal;
  final BitAddress address;
}

/// Resolves plant I/O bindings against the PLC memory and tag table.
/// Bindings may name an absolute address (`%I0.0`) or a tag (`Start`).
final class IoResolution {
  IoResolution._(this.inputs, this.outputs, this.diagnostics);

  /// Plant signal → PLC input (%I).
  final List<ResolvedBinding> inputs;

  /// PLC output (%Q) → plant signal.
  final List<ResolvedBinding> outputs;
  final List<IoDiagnostic> diagnostics;

  bool get hasErrors => diagnostics.any((d) => d.isError);

  static IoResolution resolve({
    required List<IoBinding> bindings,
    required List<Tag> tags,
    required PlcConfig config,
    String Function(String elementId)? labelOf,
  }) {
    final tagAddresses = <String, BitAddress?>{
      for (final tag in tags) tag.name.toLowerCase(): BitAddress.tryParse(tag.address),
    };
    final inputs = <ResolvedBinding>[];
    final outputs = <ResolvedBinding>[];
    final diagnostics = <IoDiagnostic>[];
    final inputOwners = <BitAddress, String>{};

    for (final b in bindings) {
      final name = labelOf?.call(b.elementId) ?? b.elementId;
      void error(IoDiagnosticCode code, String message) =>
          diagnostics.add(IoDiagnostic(Severity.error, code, message, elementId: b.elementId, signal: b.signal));

      final text = b.address.trim();
      final unquoted =
          text.length >= 2 && text.startsWith('"') && text.endsWith('"') ? text.substring(1, text.length - 1) : text;
      BitAddress? address = BitAddress.tryParse(unquoted);
      if (address == null) {
        if (unquoted.startsWith('%')) {
          error(IoDiagnosticCode.invalidAddress, 'Nieprawidłowy adres „$text” sygnału ${b.signal} elementu „$name”.');
          continue;
        }
        final key = unquoted.toLowerCase();
        if (!tagAddresses.containsKey(key)) {
          error(IoDiagnosticCode.unknownTag, 'Nieznana zmienna „$text” przypisana do elementu „$name”.');
          continue;
        }
        address = tagAddresses[key];
        // An invalid tag address is reported by the PLC compiler.
        if (address == null) continue;
      }
      if (!config.contains(address)) {
        error(IoDiagnosticCode.addressOutOfRange, 'Adres $address elementu „$name” jest poza zakresem pamięci.');
        continue;
      }

      final resolved = ResolvedBinding(b.elementId, b.signal, address);
      if (b.direction == SignalDirection.toPlc) {
        if (address.area != MemoryArea.input) {
          error(IoDiagnosticCode.wrongArea, 'Sygnał elementu „$name” musi trafiać na wejście %I, a nie na $address.');
          continue;
        }
        final owner = inputOwners[address];
        if (owner != null) {
          error(IoDiagnosticCode.inputConflict, 'Wejście $address jest już używane przez element „$owner”.');
          continue;
        }
        inputOwners[address] = name;
        inputs.add(resolved);
      } else {
        if (address.area != MemoryArea.output) {
          error(IoDiagnosticCode.wrongArea, 'Element „$name” musi być sterowany z wyjścia %Q, a nie z $address.');
          continue;
        }
        outputs.add(resolved);
      }
    }
    return IoResolution._(List.unmodifiable(inputs), List.unmodifiable(outputs), List.unmodifiable(diagnostics));
  }
}
