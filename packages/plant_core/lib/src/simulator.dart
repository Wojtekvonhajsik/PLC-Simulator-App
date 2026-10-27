import 'dart:math';

import 'catalog.dart';
import 'diagnostics.dart';
import 'element_type.dart';
import 'model.dart';
import 'params.dart';

/// Electrical signal of an element bound to a PLC address.
final class IoBinding {
  const IoBinding(this.elementId, this.signal, this.direction, this.address);

  final String elementId;
  final String signal;
  final SignalDirection direction;
  final String address;
}

final class PlantBuildResult {
  const PlantBuildResult(this.diagnostics, this.simulator);

  final List<PlantDiagnostic> diagnostics;

  /// Null when [diagnostics] contain errors.
  final PlantSimulator? simulator;

  bool get hasErrors => simulator == null;
  Iterable<PlantDiagnostic> get errors => diagnostics.where((d) => d.isError);
  Iterable<PlantDiagnostic> get warnings => diagnostics.where((d) => !d.isError);
}

/// Validates [model] and creates a simulator for it.
PlantBuildResult buildPlant(PlantModel model, {ElementCatalog? catalog}) =>
    _PlantBuilder(model, catalog ?? ElementCatalog.standard).run();

final class _PlantBuilder {
  _PlantBuilder(this.model, this.catalog);

  final PlantModel model;
  final ElementCatalog catalog;
  final _diagnostics = <PlantDiagnostic>[];
  final _elements = <String, ElementRuntime>{};

  PlantBuildResult run() {
    _buildElements();
    final tubes = _checkConnections();
    final mounts = _checkMounts();
    _checkSupply();
    if (_diagnostics.any((d) => d.isError)) return PlantBuildResult(List.unmodifiable(_diagnostics), null);
    return PlantBuildResult(List.unmodifiable(_diagnostics), PlantSimulator._(_elements, tubes, mounts));
  }

  void _buildElements() {
    for (final element in model.elements) {
      final id = element.id;
      if (id.isEmpty || _elements.containsKey(id)) {
        _error(PlantDiagnosticCode.duplicateId, 'Pusty lub powtórzony identyfikator elementu „$id”.', id);
        continue;
      }
      final type = catalog[element.type];
      if (type == null) {
        _error(PlantDiagnosticCode.unknownType, 'Nieznany typ elementu „${element.type}”.', id);
        continue;
      }
      final params = resolveParams(type.params, element.params, (m) => _error(PlantDiagnosticCode.invalidParam, m, id));
      final runtime = ElementRuntime(element, type, params);
      _elements[id] = runtime;

      for (final MapEntry(key: signal, value: address) in element.io.entries) {
        if (!runtime.signals.containsKey(signal)) {
          _error(PlantDiagnosticCode.unknownSignal, 'Element „${_name(id)}” nie ma sygnału „$signal”.', id);
        } else if (address.trim().isEmpty) {
          _unbound(runtime, signal);
        }
      }
      for (final signal in runtime.signals.keys) {
        if (!element.io.containsKey(signal)) _unbound(runtime, signal);
      }
    }
  }

  void _unbound(ElementRuntime runtime, String signal) => _warning(PlantDiagnosticCode.unboundSignal,
      'Sygnał „$signal” elementu „${_name(runtime.id)}” nie ma przypisanego adresu PLC.', runtime.id);

  List<Connection> _checkConnections() {
    final valid = <Connection>[];
    final ids = <String>{};
    final pairs = <String>{};
    final connected = <PortRef>{};
    for (final c in model.connections) {
      if (c.id.isEmpty || !ids.add(c.id)) {
        _error(PlantDiagnosticCode.duplicateId, 'Pusty lub powtórzony identyfikator połączenia „${c.id}”.', null, c.id);
        continue;
      }
      if (!_portExists(c.from, c.id) || !_portExists(c.to, c.id)) continue;
      if (c.from == c.to) {
        _error(PlantDiagnosticCode.selfConnection, 'Port ${c.from} jest połączony sam ze sobą.', null, c.id);
        continue;
      }
      final key = ([c.from.toString(), c.to.toString()]..sort()).join('|');
      if (!pairs.add(key)) {
        _warning(PlantDiagnosticCode.duplicateConnection, 'Porty ${c.from} i ${c.to} są połączone wielokrotnie.', null,
            c.id);
      }
      connected
        ..add(c.from)
        ..add(c.to);
      valid.add(c);
    }

    for (final e in _elements.values) {
      for (final port in e.type.ports) {
        if (!port.exhaust && !connected.contains(PortRef(e.id, port.id))) {
          _warning(PlantDiagnosticCode.unconnectedPort,
              'Port ${port.id} elementu „${_name(e.id)}” nie jest podłączony.', e.id);
        }
      }
    }
    return valid;
  }

  bool _portExists(PortRef ref, String connectionId) {
    final element = _elements[ref.elementId];
    if (element == null) {
      if (!model.elements.any((e) => e.id == ref.elementId)) {
        _error(PlantDiagnosticCode.unknownElement,
            'Połączenie prowadzi do nieistniejącego elementu „${ref.elementId}”.', null, connectionId);
      }
      return false; // invalid element already reported
    }
    if (!element.type.ports.any((p) => p.id == ref.port)) {
      _error(PlantDiagnosticCode.unknownPort, 'Element „${_name(ref.elementId)}” nie ma portu „${ref.port}”.',
          ref.elementId, connectionId);
      return false;
    }
    return true;
  }

  Map<String, SensorMount> _checkMounts() {
    final mounts = <String, SensorMount>{};
    for (final m in model.mounts) {
      final sensor = _elements[m.sensorId];
      final cylinder = _elements[m.cylinderId];
      if (sensor == null || cylinder == null) {
        final missing = sensor == null ? m.sensorId : m.cylinderId;
        _error(PlantDiagnosticCode.unknownElement,
            'Montaż czujnika odwołuje się do nieistniejącego elementu „$missing”.', missing);
        continue;
      }
      if (!sensor.type.mountable) {
        _error(PlantDiagnosticCode.sensorNotMountable,
            'Element „${_name(sensor.id)}” nie może być montowany na siłowniku.', sensor.id);
        continue;
      }
      if (cylinder.type is! CylinderType) {
        _error(PlantDiagnosticCode.mountTargetNotCylinder,
            'Czujnik „${_name(sensor.id)}” można zamontować tylko na siłowniku.', sensor.id);
        continue;
      }
      if (mounts.containsKey(sensor.id)) {
        _error(PlantDiagnosticCode.sensorMountedTwice, 'Czujnik „${_name(sensor.id)}” jest zamontowany wielokrotnie.',
            sensor.id);
        continue;
      }
      if (m.position < 0 || m.position > 1) {
        _error(PlantDiagnosticCode.mountPositionOutOfRange,
            'Pozycja czujnika „${_name(sensor.id)}” musi mieścić się w skoku siłownika.', sensor.id);
        continue;
      }
      final type = sensor.type;
      if (type is MountedSensorType && type.requiresMagnet && !cylinder.params.boolean('magnetic_piston')) {
        _warning(
            PlantDiagnosticCode.reedWithoutMagnet,
            'Kontaktron „${_name(sensor.id)}” nie zadziała: siłownik „${_name(cylinder.id)}” nie ma tłoka magnetycznego.',
            sensor.id);
      }
      mounts[sensor.id] = m;
    }
    for (final e in _elements.values) {
      if (e.type.mountable && !mounts.containsKey(e.id)) {
        _warning(
            PlantDiagnosticCode.unmountedSensor, 'Czujnik „${_name(e.id)}” nie jest zamontowany na siłowniku.', e.id);
      }
    }
    return mounts;
  }

  void _checkSupply() {
    final pneumatic = _elements.values.any((e) => e.type.ports.isNotEmpty);
    final supply = _elements.values.any((e) => e.type is AirSupplyType);
    if (pneumatic && !supply) {
      _warning(PlantDiagnosticCode.noAirSupply, 'Schemat nie ma źródła sprężonego powietrza.');
    }
  }

  String _name(String id) {
    final label = _elements[id]?.element.label ?? '';
    return label.isEmpty ? id : label;
  }

  void _error(PlantDiagnosticCode code, String message, [String? elementId, String? connectionId]) => _diagnostics
      .add(PlantDiagnostic(Severity.error, code, message, elementId: elementId, connectionId: connectionId));

  void _warning(PlantDiagnosticCode code, String message, [String? elementId, String? connectionId]) => _diagnostics
      .add(PlantDiagnostic(Severity.warning, code, message, elementId: elementId, connectionId: connectionId));
}

final class _UnionFind {
  _UnionFind(int size) : _parent = List.generate(size, (i) => i);

  final List<int> _parent;

  int find(int i) {
    while (_parent[i] != i) {
      _parent[i] = _parent[_parent[i]];
      i = _parent[i];
    }
    return i;
  }

  void union(int a, int b) => _parent[find(a)] = find(b);
}

typedef _Throttle = (ElementRuntime flowControl, String nearPort);

/// Qualitative electro-pneumatic simulation with a fixed time step.
///
/// Each [step]: valves switch from signals and controls → line states are
/// solved (supplied / vented / shorted / trapped) → cylinders move → sensors
/// and contacts update their output signals.
final class PlantSimulator implements SimView {
  PlantSimulator._(this._elements, List<Connection> tubes, this._mounts) {
    for (final e in _elements.values) {
      for (final port in e.type.ports) {
        final ref = PortRef(e.id, port.id);
        _index[ref] = _ports.length;
        _ports.add(ref);
      }
    }
    final connected = <int>{};
    for (final c in tubes) {
      final a = _index[c.from]!;
      final b = _index[c.to]!;
      _tubes.add((a, b));
      connected
        ..add(a)
        ..add(b);
      _adjacency.putIfAbsent(c.from, () => []).add(c.to);
      _adjacency.putIfAbsent(c.to, () => []).add(c.from);
    }
    for (final e in _elements.values) {
      for (final port in e.type.ports) {
        final i = _index[PortRef(e.id, port.id)]!;
        if (port.ventsWhenOpen && !connected.contains(i)) _open.add(i);
        if (e.behavior.isSource(port.id)) _sources.add(i);
      }
    }
    _lines = List.filled(_ports.length, LineState.trappedEmpty);
    _runPhases(0, move: false);
  }

  final Map<String, ElementRuntime> _elements;
  final Map<String, SensorMount> _mounts;
  final _ports = <PortRef>[];
  final _index = <PortRef, int>{};
  final _tubes = <(int, int)>[];
  final _adjacency = <PortRef, List<PortRef>>{};
  final _open = <int>{};
  final _sources = <int>{};
  final _throttles = <PortRef, List<_Throttle>>{};
  late List<LineState> _lines;
  int _timeMs = 0;

  int get timeMs => _timeMs;

  void step(int dtMs) {
    if (dtMs <= 0) throw ArgumentError.value(dtMs, 'dtMs', 'must be positive');
    _runPhases(dtMs, move: true);
    _timeMs += dtMs;
  }

  void _runPhases(int dtMs, {required bool move}) {
    for (final e in _elements.values) {
      e.behavior.actuate();
    }
    _solveLines();
    if (move) {
      for (final e in _elements.values) {
        e.behavior.move(this, dtMs);
      }
    }
    for (final e in _elements.values) {
      e.behavior.sense(this);
    }
  }

  void _solveLines() {
    final uf = _UnionFind(_ports.length);
    for (final (a, b) in _tubes) {
      uf.union(a, b);
    }
    for (final e in _elements.values) {
      e.behavior.passages((a, b) => uf.union(_index[PortRef(e.id, a)]!, _index[PortRef(e.id, b)]!));
    }
    final supplied = <int>{};
    final vented = <int>{};
    final trapped = <int>{};
    for (var i = 0; i < _ports.length; i++) {
      final root = uf.find(i);
      if (_sources.contains(i)) supplied.add(root);
      if (_open.contains(i)) vented.add(root);
      if (_lines[i].hasPressure) trapped.add(root);
    }
    for (var i = 0; i < _ports.length; i++) {
      final root = uf.find(i);
      final s = supplied.contains(root);
      final v = vented.contains(root);
      _lines[i] = s && v
          ? LineState.shorted
          : s
              ? LineState.supplied
              : v
                  ? LineState.vented
                  : trapped.contains(root)
                      ? LineState.trappedPressure
                      : LineState.trappedEmpty;
    }
  }

  // --------------------------------------------------------------- SimView

  @override
  LineState line(PortRef port) {
    final i = _index[port];
    if (i == null) throw ArgumentError.value(port, 'port', 'unknown port');
    return _lines[i];
  }

  @override
  CylinderBehavior? cylinder(String elementId) {
    final behavior = _elements[elementId]?.behavior;
    return behavior is CylinderBehavior ? behavior : null;
  }

  @override
  SensorMount? mountOf(String sensorId) => _mounts[sensorId];

  @override
  double flowFactor(String cylinderId, String port, {required bool filling}) {
    final throttles =
        _throttles.putIfAbsent(PortRef(cylinderId, port), () => _findThrottles(PortRef(cylinderId, port)));
    var factor = 1.0;
    for (final (flowControl, near) in throttles) {
      // Air entering the chamber flows far → near; leaving, near → far.
      // The throttled direction is 1 → 2, or both without the check valve.
      final throttled = !flowControl.params.boolean('check_valve') || (filling ? near == '2' : near == '1');
      if (throttled) factor = min(factor, flowControl.params.number('opening'));
    }
    return factor;
  }

  /// Flow control valves in the tubing between a cylinder port and the next
  /// valve, with the port that faces the cylinder.
  List<_Throttle> _findThrottles(PortRef start) {
    final result = <_Throttle>[];
    final visited = {start};
    final queue = [start];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final next in _adjacency[current] ?? const <PortRef>[]) {
        if (!visited.add(next)) continue;
        queue.add(next);
        final element = _elements[next.elementId]!;
        if (element.type is FlowControlType || element.type is ServiceUnitType) {
          if (element.type is FlowControlType) result.add((element, next.port));
          final other = PortRef(element.id, next.port == '1' ? '2' : '1');
          if (visited.add(other)) queue.add(other);
        }
      }
    }
    return result;
  }

  // --------------------------------------------------------- state access

  Iterable<String> get elementIds => _elements.keys;

  ValveBehavior? valve(String elementId) {
    final behavior = _elements[elementId]?.behavior;
    return behavior is ValveBehavior ? behavior : null;
  }

  SensorBehavior? sensor(String elementId) {
    final behavior = _elements[elementId]?.behavior;
    return behavior is SensorBehavior ? behavior : null;
  }

  IndicatorBehavior? indicator(String elementId) {
    final behavior = _elements[elementId]?.behavior;
    return behavior is IndicatorBehavior ? behavior : null;
  }

  ElementRuntime _element(String id) =>
      _elements[id] ?? (throw ArgumentError.value(id, 'elementId', 'unknown element'));

  bool signal(String elementId, String signal) {
    final e = _element(elementId);
    if (!e.signals.containsKey(signal)) throw ArgumentError.value(signal, 'signal', 'unknown signal');
    return e.signals[signal]!;
  }

  /// Drives a solenoid, lamp or buzzer from a PLC output. Takes effect at the next [step].
  void setSignal(String elementId, String signal, bool value) {
    final e = _element(elementId);
    final def = e.type.signals(e.params).where((s) => s.id == signal).firstOrNull;
    if (def == null) throw ArgumentError.value(signal, 'signal', 'unknown signal');
    if (def.direction != SignalDirection.fromPlc) {
      throw ArgumentError.value(signal, 'signal', 'is produced by the plant, not by the PLC');
    }
    e.signals[signal] = value;
  }

  bool control(String elementId, String control) {
    final e = _element(elementId);
    if (!e.controls.containsKey(control)) throw ArgumentError.value(control, 'control', 'unknown control');
    return e.controls[control]!;
  }

  /// Operator action: press a button, flip a switch, override a valve. Takes effect at the next [step].
  void setControl(String elementId, String control, bool value) {
    final e = _element(elementId);
    if (!e.controls.containsKey(control)) throw ArgumentError.value(control, 'control', 'unknown control');
    e.controls[control] = value;
  }

  /// Signals bound to PLC addresses.
  List<IoBinding> get bindings => [
        for (final e in _elements.values)
          for (final s in e.type.signals(e.params))
            if (e.element.io[s.id]?.trim() case final address? when address.isNotEmpty)
              IoBinding(e.id, s.id, s.direction, address),
      ];
}
