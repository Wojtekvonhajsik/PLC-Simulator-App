import 'address.dart';
import 'data_types.dart';
import 'diagnostics.dart';
import 'executable.dart';
import 'ladder.dart';
import 'memory.dart';
import 'tags.dart';

/// Timer or counter instance created by a box in the program.
final class InstanceInfo {
  InstanceInfo._(this.name, this.index, {this.timerKind, this.counterKind});

  final String name;
  final int index;
  final TimerKind? timerKind;
  final CounterKind? counterKind;

  bool get isTimer => timerKind != null;

  int _calls = 0;
}

final class CompiledNetwork {
  const CompiledNetwork(this.id, this.root);

  final String id;
  final ExecNode root;
}

/// Program ready to be executed by a [PlcRuntime]. Immutable and reusable:
/// several runtimes can run the same compiled program.
final class CompiledProgram {
  CompiledProgram._(this.config, this.networks, this._symbols, this.timers, this.counters);

  final PlcConfig config;
  final List<CompiledNetwork> networks;
  final Map<String, BitAddress> _symbols;
  final List<InstanceInfo> timers;
  final List<InstanceInfo> counters;

  /// Address of a tag (case-insensitive), or null if the tag does not exist.
  BitAddress? addressOf(String tagName) => _symbols[tagName.toLowerCase()];
}

final class CompileResult {
  const CompileResult(this.diagnostics, this.program);

  final List<Diagnostic> diagnostics;

  /// Null when [diagnostics] contain errors.
  final CompiledProgram? program;

  bool get hasErrors => program == null;
  Iterable<Diagnostic> get errors => diagnostics.where((d) => d.isError);
  Iterable<Diagnostic> get warnings => diagnostics.where((d) => !d.isError);
}

CompileResult compile(
  Program program, {
  List<Tag> tags = const [],
  PlcConfig config = const PlcConfig(),
}) =>
    _Compiler(program, tags, config).run();

sealed class _Operand {}

final class _AddressOperand extends _Operand {
  _AddressOperand(this.address);
  final BitAddress address;
}

final class _BitOperand extends _Operand {
  _BitOperand(this.source);
  final BitSource source;
}

final class _ValueOperand extends _Operand {
  _ValueOperand(this.type, this.source, [this.constant]);
  final DataType type;
  final ValueSource source;
  final int? constant;
}

const _timerMembers = {'Q', 'ET', 'PT'};
const _counterMembers = {
  CounterKind.ctu: {'Q', 'CV', 'PV'},
  CounterKind.ctd: {'Q', 'CV', 'PV'},
  CounterKind.ctud: {'QU', 'QD', 'CV', 'PV'},
};

final class _Compiler {
  _Compiler(this.program, this.tags, this.config);

  final Program program;
  final List<Tag> tags;
  final PlcConfig config;

  final _diagnostics = <Diagnostic>[];
  final _symbols = <String, BitAddress>{};
  final _instances = <String, InstanceInfo>{};
  final _timers = <InstanceInfo>[];
  final _counters = <InstanceInfo>[];
  final _ids = <String>{};
  final _assigned = <BitAddress>{};
  final _edgeMemories = <BitAddress>{};
  String? _networkId;

  CompileResult run() {
    _buildSymbols();
    _collectInstances();
    final networks = <CompiledNetwork>[];
    for (final network in program.networks) {
      _networkId = network.id;
      _checkId(network.id, null);
      final rung = network.rung;
      if (rung.children.isEmpty) continue;
      if (!_endsWithOutput(rung)) {
        _error(DiagnosticCode.networkIncomplete, 'Sieć jest niekompletna: musi kończyć się cewką lub blokiem.');
      }
      networks.add(CompiledNetwork(network.id, _node(rung)));
    }
    _networkId = null;
    final hasErrors = _diagnostics.any((d) => d.isError);
    return CompileResult(
      List.unmodifiable(_diagnostics),
      hasErrors
          ? null
          : CompiledProgram._(config, List.unmodifiable(networks), Map.unmodifiable(_symbols),
              List.unmodifiable(_timers), List.unmodifiable(_counters)),
    );
  }

  // ---------------------------------------------------------------- tags

  void _buildSymbols() {
    final addresses = <BitAddress, String>{};
    for (final tag in tags) {
      if (!isValidIdentifier(tag.name)) {
        _tagError(tag, DiagnosticCode.invalidTagName, 'Nieprawidłowa nazwa zmiennej „${tag.name}”.');
        continue;
      }
      final key = tag.name.toLowerCase();
      if (_symbols.containsKey(key)) {
        _tagError(tag, DiagnosticCode.duplicateTagName, 'Zmienna „${tag.name}” jest zdefiniowana wielokrotnie.');
        continue;
      }
      final address = BitAddress.tryParse(tag.address);
      if (address == null) {
        _tagError(tag, DiagnosticCode.invalidAddress, 'Nieprawidłowy adres „${tag.address}”.');
        continue;
      }
      if (!config.contains(address)) {
        _tagError(tag, DiagnosticCode.addressOutOfRange, 'Adres $address jest poza zakresem pamięci.');
        continue;
      }
      final other = addresses[address];
      if (other != null) {
        _diagnostics.add(Diagnostic(Severity.warning, DiagnosticCode.duplicateTagAddress,
            'Adres $address jest używany także przez zmienną „$other”.',
            tagName: tag.name));
      } else {
        addresses[address] = tag.name;
      }
      _symbols[key] = address;
    }
  }

  void _tagError(Tag tag, DiagnosticCode code, String message) =>
      _diagnostics.add(Diagnostic(Severity.error, code, message, tagName: tag.name));

  // ----------------------------------------------------------- instances

  void _collectInstances() {
    for (final network in program.networks) {
      _networkId = network.id;
      for (final node in _walk(network.rung)) {
        switch (node) {
          case TimerBox(:final instance, :final kind):
            _declareInstance(node.id, instance, timerKind: kind);
          case CounterBox(:final instance, :final kind):
            _declareInstance(node.id, instance, counterKind: kind);
          default:
        }
      }
    }
  }

  void _declareInstance(String elementId, String rawName, {TimerKind? timerKind, CounterKind? counterKind}) {
    final name = _clean(rawName);
    if (!isValidIdentifier(name)) {
      _error(DiagnosticCode.invalidInstanceName, 'Nieprawidłowa nazwa instancji „$name”.', elementId);
      return;
    }
    final key = name.toLowerCase();
    if (_symbols.containsKey(key)) {
      _error(DiagnosticCode.instanceNameCollision, 'Nazwa instancji „$name” jest już użyta przez zmienną.', elementId);
      return;
    }
    final existing = _instances[key];
    if (existing != null) {
      if (existing.timerKind != timerKind || existing.counterKind != counterKind) {
        _error(
            DiagnosticCode.instanceKindConflict, 'Instancja „$name” jest używana przez bloki różnego typu.', elementId);
      }
      return;
    }
    final InstanceInfo info;
    if (timerKind != null) {
      info = InstanceInfo._(name, _timers.length, timerKind: timerKind);
      _timers.add(info);
    } else {
      info = InstanceInfo._(name, _counters.length, counterKind: counterKind);
      _counters.add(info);
    }
    _instances[key] = info;
  }

  InstanceInfo? _callInstance(String elementId, String rawName) {
    final info = _instances[_clean(rawName).toLowerCase()];
    if (info == null) return null; // already reported while collecting
    if (++info._calls == 2) {
      _warning(
          DiagnosticCode.instanceCalledTwice, 'Instancja „${info.name}” jest wywoływana więcej niż raz.', elementId);
    }
    return info;
  }

  // ---------------------------------------------------------- structure

  static Iterable<LadNode> _walk(LadNode node) sync* {
    yield node;
    switch (node) {
      case Series(:final children):
        for (final child in children) {
          yield* _walk(child);
        }
      case Parallel(:final branches):
        for (final branch in branches) {
          yield* _walk(branch);
        }
      default:
    }
  }

  static bool _endsWithOutput(Series series) {
    if (series.children.isEmpty) return false;
    return switch (series.children.last) {
      Parallel(:final branches) => branches.isNotEmpty && branches.every(_endsWithOutput),
      Coil() || EdgeCoil() || FlipFlopBox() || TimerBox() || CounterBox() => true,
      _ => false,
    };
  }

  void _checkId(String id, String? elementId) {
    if (id.isEmpty || !_ids.add(id)) {
      _error(DiagnosticCode.duplicateId, 'Pusty lub powtórzony identyfikator „$id”.', elementId);
    }
  }

  ExecNode _node(LadNode node) {
    _checkId(node.id, node.id);
    final id = node.id;
    switch (node) {
      case Series(:final children):
        return SeriesExec(id, [for (final child in children) _node(child)]);
      case Parallel(:final branches):
        if (branches.length < 2) {
          _warning(DiagnosticCode.singleBranch, 'Rozgałęzienie równoległe ma mniej niż dwie gałęzie.', id);
        }
        for (final branch in branches) {
          if (branch.children.isEmpty) {
            _warning(DiagnosticCode.emptyBranch, 'Pusta gałąź zwiera rozgałęzienie.', branch.id);
          }
        }
        return ParallelExec(id, [for (final branch in branches) _node(branch)]);
      case Contact(:final kind, :final operand):
        return ContactExec(id, _readBit(operand, id), normallyClosed: kind == ContactKind.normallyClosed);
      case NotContact():
        return NotExec(id);
      case EdgeContact(:final kind, :final operand, :final memoryBit):
        return EdgeContactExec(id, kind, _readBit(operand, id), _edgeMemory(memoryBit, id));
      case CompareContact(:final op, :final in1, :final in2):
        final values = _sameTypeValues([in1, in2], id);
        return CompareExec(id, op, values[0], values[1]);
      case RangeContact(:final kind, :final min, :final value, :final max):
        final values = _sameTypeValues([min, value, max], id);
        return RangeExec(id, kind, values[0], values[1], values[2]);
      case Coil(:final kind, :final operand):
        final target = _writeBit(operand, id);
        if (kind == CoilKind.assign || kind == CoilKind.negated) _trackAssignment(target, id);
        return CoilExec(id, kind, target ?? _placeholder);
      case EdgeCoil(:final kind, :final operand, :final memoryBit):
        final target = _writeBit(operand, id);
        _trackAssignment(target, id);
        return EdgeCoilExec(id, kind, target ?? _placeholder, _edgeMemory(memoryBit, id));
      case FlipFlopBox(:final kind, :final operand, :final secondInput):
        return FlipFlopExec(id, kind, _writeBit(operand, id) ?? _placeholder, _readBit(secondInput, id));
      case TriggerBox(:final kind, :final memoryBit):
        return TriggerExec(id, kind, _edgeMemory(memoryBit, id));
      case TimerBox():
        return _timer(node);
      case CounterBox():
        return _counter(node);
    }
  }

  ExecNode _timer(TimerBox box) {
    final id = box.id;
    final info = _callInstance(id, box.instance);
    final preset = _value(box.presetTime, id, DataType.time);
    if (preset case _ValueOperand(constant: final c?) when c < 0) {
      _error(DiagnosticCode.negativeTime, 'Czas PT nie może być ujemny.', id);
    }
    BitSource? reset;
    if (box.reset != null) {
      if (box.kind == TimerKind.tonr) {
        reset = _readBit(box.reset!, id);
      } else {
        _unsupported('R', box.kind.name, id);
      }
    }
    return TimerExec(id, info?.index ?? 0, preset?.source ?? const ConstValue(0), reset);
  }

  ExecNode _counter(CounterBox box) {
    final id = box.id;
    final info = _callInstance(id, box.instance);
    final preset = _value(box.presetValue, id, DataType.integer);
    BitSource? optional(String? operand, String input, Set<CounterKind> allowed) {
      if (operand == null) return null;
      if (!allowed.contains(box.kind)) {
        _unsupported(input, box.kind.name, id);
        return null;
      }
      return _readBit(operand, id);
    }

    return CounterExec(
      id,
      info?.index ?? 0,
      preset?.source ?? const ConstValue(0),
      countDown: optional(box.countDown, 'CD', {CounterKind.ctud}),
      reset: optional(box.reset, 'R', {CounterKind.ctu, CounterKind.ctud}),
      load: optional(box.load, 'LD', {CounterKind.ctd, CounterKind.ctud}),
    );
  }

  void _unsupported(String input, String kind, String id) =>
      _error(DiagnosticCode.unsupportedInput, 'Blok ${kind.toUpperCase()} nie ma wejścia $input.', id);

  void _trackAssignment(AreaBit? target, String id) {
    if (target != null && !_assigned.add(target.address)) {
      _warning(DiagnosticCode.doubleCoil, 'Podwójna cewka: ${target.address} jest przypisywany w kilku miejscach.', id);
    }
  }

  // ----------------------------------------------------------- operands

  static String _clean(String text) {
    final t = text.trim();
    return t.length >= 2 && t.startsWith('"') && t.endsWith('"') ? t.substring(1, t.length - 1) : t;
  }

  _Operand? _resolve(String raw, String id) {
    final text = _clean(raw);
    if (text.isEmpty) {
      _error(DiagnosticCode.emptyOperand, 'Brak operandu.', id);
      return null;
    }
    final upper = text.toUpperCase();
    if (upper == 'TRUE' || upper == 'FALSE') return _BitOperand(ConstBit(upper == 'TRUE'));

    if (looksLikeTimeLiteral(text) || (text.startsWith('-') && looksLikeTimeLiteral(text.substring(1)))) {
      final ms = parseTimeLiteral(text);
      if (ms == null) {
        _error(DiagnosticCode.invalidLiteral, 'Nieprawidłowa stała czasu „$text”.', id);
        return null;
      }
      return _ValueOperand(DataType.time, ConstValue(ms), ms);
    }
    if (looksLikeIntLiteral(text)) {
      final value = parseIntLiteral(text);
      if (value == null) {
        _error(DiagnosticCode.invalidLiteral, 'Stała „$text” jest poza zakresem INT ($intMin…$intMax).', id);
        return null;
      }
      return _ValueOperand(DataType.integer, ConstValue(value), value);
    }

    final address = BitAddress.tryParse(text);
    if (address != null) return _checkedAddress(address, id);
    if (text.startsWith('%')) {
      _error(DiagnosticCode.invalidAddress, 'Nieprawidłowy adres „$text”.', id);
      return null;
    }

    final dot = text.indexOf('.');
    if (dot >= 0) return _member(text.substring(0, dot), text.substring(dot + 1), id);

    final symbol = _symbols[text.toLowerCase()];
    if (symbol != null) return _AddressOperand(symbol);
    _error(DiagnosticCode.unknownOperand, 'Nieznany operand „$text”.', id);
    return null;
  }

  _Operand? _checkedAddress(BitAddress address, String id) {
    if (!config.contains(address)) {
      _error(DiagnosticCode.addressOutOfRange, 'Adres $address jest poza zakresem pamięci.', id);
      return null;
    }
    return _AddressOperand(address);
  }

  _Operand? _member(String instanceName, String rawMember, String id) {
    final info = _instances[instanceName.toLowerCase()];
    if (info == null) {
      _error(DiagnosticCode.unknownInstance, 'Nieznana instancja „$instanceName”.', id);
      return null;
    }
    final member = rawMember.toUpperCase();
    final index = info.index;
    if (info.isTimer) {
      if (!_timerMembers.contains(member)) return _unknownMember(info, rawMember, id);
      return switch (member) {
        'Q' => _BitOperand(MemberBit((ctx) => ctx.timers[index].q)),
        'ET' => _ValueOperand(DataType.time, MemberValue((ctx) => ctx.timers[index].et)),
        _ => _ValueOperand(DataType.time, MemberValue((ctx) => ctx.timers[index].pt)),
      };
    }
    if (!_counterMembers[info.counterKind]!.contains(member)) return _unknownMember(info, rawMember, id);
    return switch (member) {
      'Q' => _BitOperand(MemberBit((ctx) => ctx.counters[index].q)),
      'QU' => _BitOperand(MemberBit((ctx) => ctx.counters[index].qu)),
      'QD' => _BitOperand(MemberBit((ctx) => ctx.counters[index].qd)),
      'CV' => _ValueOperand(DataType.integer, MemberValue((ctx) => ctx.counters[index].cv)),
      _ => _ValueOperand(DataType.integer, MemberValue((ctx) => ctx.counters[index].pv)),
    };
  }

  _Operand? _unknownMember(InstanceInfo info, String member, String id) {
    _error(DiagnosticCode.unknownMember, 'Instancja „${info.name}” nie ma pola „$member”.', id);
    return null;
  }

  BitSource _readBit(String raw, String id) {
    switch (_resolve(raw, id)) {
      case _AddressOperand(:final address):
        return AreaBit(address);
      case _BitOperand(:final source):
        return source;
      case _ValueOperand(:final type):
        _error(DiagnosticCode.typeMismatch, 'Oczekiwano operandu BOOL, a podano ${type.label}.', id);
      case null:
    }
    return const ConstBit(false);
  }

  static const _placeholder = AreaBit(BitAddress(MemoryArea.marker, 0, 0));

  /// Writable bit (%Q or %M), or null after reporting an error.
  AreaBit? _writeBit(String raw, String id) {
    switch (_resolve(raw, id)) {
      case _AddressOperand(:final address):
        if (address.area == MemoryArea.input) {
          _error(DiagnosticCode.writeToInput, 'Nie można zapisywać wejścia $address.', id);
          return null;
        }
        return AreaBit(address);
      case _BitOperand() || _ValueOperand():
        _error(DiagnosticCode.readOnlyOperand, 'Operand „${_clean(raw)}” jest tylko do odczytu.', id);
      case null:
    }
    return null;
  }

  AreaBit _edgeMemory(String raw, String id) {
    final bit = _writeBit(raw, id);
    if (bit == null) return _placeholder;
    if (bit.address.area != MemoryArea.marker) {
      _error(DiagnosticCode.edgeMemoryNotMarker, 'Bit pamięci zbocza musi być w obszarze %M.', id);
    }
    if (!_edgeMemories.add(bit.address)) {
      _warning(DiagnosticCode.edgeMemoryReused,
          'Bit pamięci zbocza ${bit.address} jest używany przez kilka instrukcji.', id);
    }
    return bit;
  }

  _ValueOperand? _value(String raw, String id, [DataType? expected]) {
    final operand = _resolve(raw, id);
    if (operand == null) return null;
    if (operand is! _ValueOperand) {
      _error(
          DiagnosticCode.typeMismatch, 'Oczekiwano wartości ${expected?.label ?? 'INT lub TIME'}, a podano BOOL.', id);
      return null;
    }
    if (expected != null && operand.type != expected) {
      _error(DiagnosticCode.typeMismatch, 'Oczekiwano wartości ${expected.label}, a podano ${operand.type.label}.', id);
      return null;
    }
    return operand;
  }

  List<ValueSource> _sameTypeValues(List<String> raws, String id) {
    final operands = [for (final raw in raws) _value(raw, id)];
    final types = {
      for (final o in operands)
        if (o != null) o.type
    };
    if (types.length > 1) {
      _error(DiagnosticCode.typeMismatch, 'Porównywane wartości mają różne typy.', id);
    }
    return [for (final o in operands) o?.source ?? const ConstValue(0)];
  }

  // -------------------------------------------------------- diagnostics

  void _error(DiagnosticCode code, String message, [String? elementId]) =>
      _diagnostics.add(Diagnostic(Severity.error, code, message, networkId: _networkId, elementId: elementId));

  void _warning(DiagnosticCode code, String message, [String? elementId]) =>
      _diagnostics.add(Diagnostic(Severity.warning, code, message, networkId: _networkId, elementId: elementId));
}
