import 'package:sim_engine/sim_engine.dart';
import 'package:test/test.dart';

void main() {
  final b = LadderBuilder();
  final program = Program([
    b.network([b.no('%I0.0'), b.coil('%Q0.0')]),
  ]);

  SimulationBuildResult build(PlantBuilder plant, {List<Tag> tags = const [], Program? plc}) =>
      buildSimulation(SimulationProject(program: plc ?? program, tags: tags, plant: plant.build()));

  List<IoDiagnosticCode> ioCodes(PlantBuilder plant, {List<Tag> tags = const []}) =>
      [for (final d in build(plant, tags: tags).ioDiagnostics) d.code];

  test('button drives a lamp through the PLC', () {
    final sim = build(
        PlantBuilder()
          ..element('S1', 'push_button', io: {'out': '%I0.0'})
          ..element('H1', 'lamp', io: {'in': '"Lamp"'}),
        tags: const [Tag(name: 'Lamp', address: '%Q0.0')]).simulation!
      ..start();
    sim.run(50);
    expect(sim.plant.indicator('H1')!.isOn, isFalse);
    sim.plant.setControl('S1', 'press', true);
    sim.step(); // plant updates the contact, PLC scans, lamp is driven
    expect(sim.plant.indicator('H1')!.isOn, isTrue);
  });

  test('initial sensor states reach the PLC before the first scan', () {
    final sim = build(PlantBuilder()..element('ES', 'emergency_stop', io: {'out': '%I0.0'})).simulation!;
    expect(sim.plc.inputSignal(BitAddress.parse('%I0.0')), isTrue);
  });

  group('binding errors', () {
    test('invalid address, unknown tag, out of range', () {
      expect(
          ioCodes(PlantBuilder()
            ..element('A', 'push_button', io: {'out': '%I0.9'})
            ..element('B', 'push_button', io: {'out': 'Nope'})
            ..element('C', 'push_button', io: {'out': '%I99.0'})),
          [IoDiagnosticCode.invalidAddress, IoDiagnosticCode.unknownTag, IoDiagnosticCode.addressOutOfRange]);
    });

    test('sensors need inputs, solenoids and lamps need outputs', () {
      expect(
          ioCodes(PlantBuilder()
            ..element('A', 'push_button', io: {'out': '%Q0.0'})
            ..element('H', 'lamp', io: {'in': '%I0.0'})
            ..element('M', 'lamp', io: {'in': '%M0.0'})),
          List.filled(3, IoDiagnosticCode.wrongArea));
    });

    test('two plant signals on one input conflict, shared outputs are fine', () {
      final result = build(
          PlantBuilder()
            ..element('A', 'push_button', label: 'S1', io: {'out': '%I0.0'})
            ..element('B', 'push_button', io: {'out': 'Start'})
            ..element('H1', 'lamp', io: {'in': '%Q0.0'})
            ..element('H2', 'buzzer', io: {'in': '%Q0.0'}),
          tags: const [Tag(name: 'Start', address: '%I0.0')]);
      expect(result.ioDiagnostics.single.code, IoDiagnosticCode.inputConflict);
      expect(result.ioDiagnostics.single.message, contains('S1'));
      expect(result.ioDiagnostics.single.elementId, 'B');
      expect(result.simulation, isNull);
    });

    test('binding errors are reported even when the schematic has errors', () {
      final result = build(PlantBuilder()
        ..element('A', 'push_button', io: {'out': '%Q0.0'})
        ..element('C', 'cylinder_double')
        ..connect('C.A', 'C.X'));
      expect(result.plant.hasErrors, isTrue);
      expect(result.ioDiagnostics.map((d) => d.code), [IoDiagnosticCode.wrongArea]);
    });
  });

  test('PLC errors block the simulation but keep the other diagnostics', () {
    final result = build(PlantBuilder()..element('H', 'lamp'),
        plc: Program([
          b.network([b.no('Nope'), b.coil('%Q0.0')])
        ]));
    expect(result.plc.hasErrors, isTrue);
    expect(result.plant.warnings, isNotEmpty);
    expect(result.simulation, isNull);
  });

  group('clock', () {
    late Simulation sim;
    setUp(() => sim = build(PlantBuilder()..element('S1', 'push_button', io: {'out': '%I0.0'})).simulation!..start());

    test('real time is converted into whole cycles', () {
      final clock = SimulationClock(sim);
      var steps = 0;
      for (var i = 0; i < 100; i++) {
        steps += clock.tick(16);
      }
      expect(steps, 160);
      expect(sim.timeMs, 1600);
    });

    test('speed, pause and single step', () {
      final clock = SimulationClock(sim)..speed = 0.5;
      clock.tick(1000);
      expect(sim.timeMs, 500);
      clock.paused = true;
      expect(clock.tick(1000), 0);
      clock.stepOnce();
      expect(sim.timeMs, 510);
      expect(() => clock.speed = 100, throwsArgumentError);
    });

    test('backlog is dropped on a slow device', () {
      final clock = SimulationClock(sim, maxStepsPerTick: 50);
      expect(clock.tick(100000), 50);
      expect(clock.tick(0), lessThanOrEqualTo(1));
    });
  });
}
