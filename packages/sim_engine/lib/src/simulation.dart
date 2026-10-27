import 'package:plant_core/plant_core.dart';
import 'package:plc_core/plc_core.dart';

import 'io_binding.dart';

/// Everything needed to run a simulation: PLC program, tag table and plant.
final class SimulationProject {
  const SimulationProject({
    required this.program,
    required this.plant,
    this.tags = const [],
    this.config = const PlcConfig(),
  });

  final Program program;
  final List<Tag> tags;
  final PlantModel plant;
  final PlcConfig config;
}

final class SimulationBuildResult {
  const SimulationBuildResult({
    required this.plc,
    required this.plant,
    required this.ioDiagnostics,
    required this.simulation,
  });

  /// PLC compilation result (diagnostics for the LAD editor and tag table).
  final CompileResult plc;

  /// Schematic validation result (diagnostics for the schematic editor).
  final PlantBuildResult plant;
  final List<IoDiagnostic> ioDiagnostics;

  /// Null when any part has errors.
  final Simulation? simulation;

  bool get hasErrors => simulation == null;
}

/// Validates the whole project and couples the PLC with the plant.
SimulationBuildResult buildSimulation(SimulationProject project, {int cycleMs = 10, ElementCatalog? catalog}) {
  if (cycleMs <= 0) throw ArgumentError.value(cycleMs, 'cycleMs', 'must be positive');
  final plc = compile(project.program, tags: project.tags, config: project.config);
  final plant = buildPlant(project.plant, catalog: catalog);
  final labels = {for (final e in project.plant.elements) e.id: e.label.isEmpty ? e.id : e.label};
  final io = IoResolution.resolve(
    bindings: plant.simulator?.bindings ?? _declaredBindings(project.plant, catalog ?? ElementCatalog.standard),
    tags: project.tags,
    config: project.config,
    labelOf: (id) => labels[id] ?? id,
  );
  final simulation = plc.hasErrors || plant.hasErrors || io.hasErrors
      ? null
      : Simulation._(PlcRuntime(plc.program!), plant.simulator!, io.inputs, io.outputs, cycleMs);
  return SimulationBuildResult(plc: plc, plant: plant, ioDiagnostics: io.diagnostics, simulation: simulation);
}

/// Bindings straight from the model, so I/O problems are reported even when
/// the schematic itself has errors.
List<IoBinding> _declaredBindings(PlantModel model, ElementCatalog catalog) => [
      for (final e in model.elements)
        if (catalog[e.type] case final type?)
          for (final MapEntry(key: signal, value: address) in e.io.entries)
            if (address.trim().isNotEmpty)
              if (_direction(type, e, signal) case final direction?) IoBinding(e.id, signal, direction, address),
    ];

SignalDirection? _direction(ElementType type, PlantElement element, String signal) {
  final params = resolveParams(type.params, element.params, (_) {});
  return type.signals(params).where((s) => s.id == signal).firstOrNull?.direction;
}

/// PLC and plant running in lockstep with a fixed cycle time.
///
/// One [step]:
/// 1. the plant advances by [cycleMs] using the PLC outputs of the previous cycle,
/// 2. sensor and button signals are copied to the PLC inputs,
/// 3. the PLC runs one scan,
/// 4. PLC outputs are copied to solenoids, lamps and buzzers.
final class Simulation {
  Simulation._(this.plc, this.plant, this.inputs, this.outputs, this.cycleMs) {
    _copyInputs();
  }

  final PlcRuntime plc;
  final PlantSimulator plant;
  final List<ResolvedBinding> inputs;
  final List<ResolvedBinding> outputs;
  final int cycleMs;
  int _timeMs = 0;

  int get timeMs => _timeMs;

  /// PLC STOP → RUN (cold restart). The plant keeps its physical state.
  void start() => plc.start();

  /// PLC RUN → STOP. Outputs drop, the plant keeps running (springs return valves).
  void stop() {
    plc.stop();
    _copyOutputs();
  }

  void step() {
    plant.step(cycleMs);
    _copyInputs();
    plc.scan(cycleMs: cycleMs);
    _copyOutputs();
    _timeMs += cycleMs;
  }

  /// Runs whole cycles covering [ms] of simulated time.
  void run(int ms) {
    for (var t = 0; t < ms; t += cycleMs) {
      step();
    }
  }

  /// Runs until [condition] holds, at most [timeoutMs]. Returns whether it holds.
  bool runUntil(bool Function() condition, {required int timeoutMs}) {
    for (var t = 0; t < timeoutMs; t += cycleMs) {
      if (condition()) return true;
      step();
    }
    return condition();
  }

  void _copyInputs() {
    for (final b in inputs) {
      plc.setInput(b.address, plant.signal(b.elementId, b.signal));
    }
  }

  void _copyOutputs() {
    for (final b in outputs) {
      plant.setSignal(b.elementId, b.signal, plc.output(b.address));
    }
  }
}
