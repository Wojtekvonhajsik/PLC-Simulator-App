import 'address.dart';
import 'compiler.dart';
import 'executable.dart';
import 'instances.dart';
import 'memory.dart';

enum PlcMode { stop, run }

/// Executes a [CompiledProgram] in scan cycles:
/// physical inputs → PII, program execution, PIQ → physical outputs.
///
/// Time is simulated: it advances only by the cycle time passed to [scan],
/// so the same inputs always give the same result.
final class PlcRuntime {
  PlcRuntime(this.program)
      : _physicalInputs = List.filled(program.config.inputBytes * 8, false),
        _physicalOutputs = List.filled(program.config.outputBytes * 8, false),
        _memory = ProcessMemory(program.config) {
    _context = _newContext();
  }

  final CompiledProgram program;
  final List<bool> _physicalInputs;
  final List<bool> _physicalOutputs;
  ProcessMemory _memory;
  late ExecContext _context;
  final Map<BitAddress, bool> _forces = {};

  PlcMode _mode = PlcMode.stop;
  int _timeMs = 0;
  int _scanCount = 0;
  Map<String, ElementStatus> _lastMonitor = const {};

  /// When true, power flow of every element is recorded during each scan.
  bool monitoring = false;

  PlcMode get mode => _mode;

  /// Simulated time since the last [start], in ms.
  int get timeMs => _timeMs;
  int get scanCount => _scanCount;

  /// Power flow per element id recorded during the last scan (empty unless [monitoring]).
  Map<String, ElementStatus> get monitor => _lastMonitor;

  Map<BitAddress, bool> get forces => Map.unmodifiable(_forces);

  ExecContext _newContext() => ExecContext(
        _memory,
        [for (final t in program.timers) TimerState(t.timerKind!)],
        [for (final c in program.counters) CounterState(c.counterKind!)],
      );

  /// STOP → RUN with a cold restart: process images, bit memory, timers and
  /// counters are cleared. Physical inputs and forces are kept.
  void start() {
    _memory = ProcessMemory(program.config);
    _context = _newContext();
    _timeMs = 0;
    _scanCount = 0;
    _lastMonitor = const {};
    _mode = PlcMode.run;
  }

  /// RUN → STOP. Physical outputs go to 0 (forced outputs keep their force value).
  void stop() {
    _mode = PlcMode.stop;
    _writeOutputs();
  }

  /// Runs one scan cycle of [cycleMs] simulated milliseconds. Does nothing in STOP.
  void scan({int cycleMs = 10}) {
    if (cycleMs <= 0) throw ArgumentError.value(cycleMs, 'cycleMs', 'must be positive');
    if (_mode == PlcMode.stop) return;
    _timeMs += cycleMs;
    _scanCount++;

    for (var i = 0; i < _physicalInputs.length; i++) {
      _memory.inputs[i] = _physicalInputs[i];
    }
    for (final MapEntry(key: address, :value) in _forces.entries) {
      if (address.area == MemoryArea.input) _memory.inputs[address.index] = value;
    }

    final monitor = monitoring ? <String, ElementStatus>{} : null;
    _context
      ..now = _timeMs
      ..monitor = monitor;
    for (final network in program.networks) {
      network.root.run(true, _context);
    }
    _lastMonitor = monitor ?? const {};

    _writeOutputs();
  }

  void _writeOutputs() {
    final running = _mode == PlcMode.run;
    for (var i = 0; i < _physicalOutputs.length; i++) {
      _physicalOutputs[i] = running && _memory.outputs[i];
    }
    for (final MapEntry(key: address, :value) in _forces.entries) {
      if (address.area == MemoryArea.output) _physicalOutputs[address.index] = value;
    }
  }

  // ------------------------------------------------------------ I/O

  /// Sets a physical input signal (e.g. from a button or a sensor).
  void setInput(BitAddress address, bool value) {
    _checkArea(address, MemoryArea.input);
    _physicalInputs[address.index] = value;
  }

  /// Physical input signal as delivered by the plant.
  bool inputSignal(BitAddress address) {
    _checkArea(address, MemoryArea.input);
    return _physicalInputs[address.index];
  }

  /// Physical output signal driving the plant.
  bool output(BitAddress address) {
    _checkArea(address, MemoryArea.output);
    return _physicalOutputs[address.index];
  }

  /// Value seen by the program: PII for %I, PIQ for %Q, bit memory for %M.
  bool readBit(BitAddress address) {
    _checkRange(address);
    return _memory.read(address);
  }

  /// Watch-table "modify": one-time write of %Q (PIQ) or %M.
  /// Inputs are driven by the plant — use [setInput] or [force].
  void modify(BitAddress address, bool value) {
    _checkRange(address);
    if (address.area == MemoryArea.input) {
      throw ArgumentError.value(address, 'address', 'inputs cannot be modified, use setInput or force');
    }
    _memory.write(address, value);
  }

  /// Forces an input or output to [value]; null removes the force.
  void force(BitAddress address, bool? value) {
    _checkRange(address);
    if (address.area == MemoryArea.marker) {
      throw ArgumentError.value(address, 'address', 'only inputs and outputs can be forced');
    }
    if (value == null) {
      _forces.remove(address);
    } else {
      _forces[address] = value;
    }
    _writeOutputs();
  }

  void clearForces() {
    _forces.clear();
    _writeOutputs();
  }

  // ------------------------------------------------------- tag access

  BitAddress _tag(String name) => program.addressOf(name) ?? (throw ArgumentError.value(name, 'name', 'unknown tag'));

  void setInputByTag(String name, bool value) => setInput(_tag(name), value);

  /// Value of a tag as seen by the program (see [readBit]).
  bool readTag(String name) => readBit(_tag(name));

  /// Physical output signal of an output tag.
  bool outputByTag(String name) => output(_tag(name));

  // -------------------------------------------------------- instances

  TimerState? timer(String name) {
    final index = program.timers.indexWhere((t) => t.name.toLowerCase() == name.toLowerCase());
    return index < 0 ? null : _context.timers[index];
  }

  CounterState? counter(String name) {
    final index = program.counters.indexWhere((c) => c.name.toLowerCase() == name.toLowerCase());
    return index < 0 ? null : _context.counters[index];
  }

  void _checkRange(BitAddress address) {
    if (!program.config.contains(address)) {
      throw RangeError('Address $address is outside the configured memory');
    }
  }

  void _checkArea(BitAddress address, MemoryArea area) {
    if (address.area != area) {
      throw ArgumentError.value(address, 'address', 'expected an ${area.name} address');
    }
    _checkRange(address);
  }
}
