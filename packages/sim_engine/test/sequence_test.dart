import 'package:sim_engine/sim_engine.dart';
import 'package:test/test.dart';

/// Two double-acting cylinders 1A and 2A, monostable 5/2 valves, reed
/// switches at both ends, start button, emergency stop, auto selector and a
/// "cycle running" lamp.
PlantModel twoCylinderPlant() {
  final p = PlantBuilder()
    ..element('S', 'air_supply')
    ..element('S1', 'push_button', label: 'Start', io: {'out': 'Start'})
    ..element('S2', 'selector_switch', label: 'Auto', io: {'out': '%I0.5'})
    ..element('ES', 'emergency_stop', io: {'out': '%I0.7'})
    ..element('H1', 'lamp', io: {'in': '%Q0.2'});
  for (final (n, y, a0, a1) in [(1, '%Q0.0', '%I0.1', '%I0.2'), (2, '%Q0.1', '%I0.3', '%I0.4')]) {
    p
      ..element('${n}V1', 'valve_5_2', io: {'14': y})
      ..element('${n}A', 'cylinder_double')
      ..element('${n}B1', 'reed_switch', io: {'out': a0})
      ..element('${n}B2', 'reed_switch', io: {'out': a1})
      ..connect('S.P', '${n}V1.1')
      ..connect('${n}V1.4', '${n}A.A')
      ..connect('${n}V1.2', '${n}A.B')
      ..mount('${n}B1', '${n}A', 0)
      ..mount('${n}B2', '${n}A', 1);
  }
  return p.build();
}

const tags = [
  Tag(name: 'Start', address: '%I0.0'),
  Tag(name: 'A0', address: '%I0.1'),
  Tag(name: 'A1', address: '%I0.2'),
  Tag(name: 'B0', address: '%I0.3'),
  Tag(name: 'B1', address: '%I0.4'),
  Tag(name: 'Auto', address: '%I0.5'),
  Tag(name: 'ES', address: '%I0.7'),
  Tag(name: 'Y1', address: '%Q0.0'),
  Tag(name: 'Y2', address: '%Q0.1'),
  Tag(name: 'Busy', address: '%Q0.2'),
  Tag(name: 'St1', address: '%M0.1'),
  Tag(name: 'St2', address: '%M0.2'),
  Tag(name: 'St3', address: '%M0.3'),
  Tag(name: 'St4', address: '%M0.4'),
];

/// A+ B+ A- B- as a step sequence with set/reset step flags.
/// With [dwellMs] the sequence waits at B+ before A-.
/// The start condition is a start button edge, or the Auto selector until
/// the cycle counter reaches 3.
Program sequenceProgram({int dwellMs = 0}) {
  final b = LadderBuilder();
  return Program([
    b.network([
      b.parallel([
        [b.posEdge('Start', '%M10.0')],
        [b.no('Auto'), b.compare('Cycles.CV', CompareOp.less, '3')],
      ]),
      b.no('A0'),
      b.no('B0'),
      b.nc('St1'),
      b.nc('St2'),
      b.nc('St3'),
      b.nc('St4'),
      b.no('ES'),
      b.setCoil('St1'),
    ], title: 'Start cyklu'),
    b.network([
      b.no('St1'),
      b.no('A1'),
      b.parallel([
        [b.setCoil('St2')],
        [b.resetCoil('St1')],
      ]),
    ], title: 'A+ wykonane → B+'),
    if (dwellMs == 0)
      b.network([
        b.no('St2'),
        b.no('B1'),
        b.parallel([
          [b.setCoil('St3')],
          [b.resetCoil('St2')],
        ]),
      ], title: 'B+ wykonane → A-')
    else ...[
      b.network([b.no('St2'), b.no('B1'), b.ton('Dwell', 'T#${dwellMs}ms')], title: 'Postój'),
      b.network([
        b.no('St2'),
        b.no('Dwell.Q'),
        b.parallel([
          [b.setCoil('St3')],
          [b.resetCoil('St2')],
        ]),
      ], title: 'Po postoju → A-'),
    ],
    b.network([
      b.no('St3'),
      b.no('A0'),
      b.parallel([
        [b.setCoil('St4')],
        [b.resetCoil('St3')],
      ]),
    ], title: 'A- wykonane → B-'),
    b.network([b.no('St4'), b.no('B0'), b.ctu('Cycles', '3')], title: 'Licznik cykli'),
    b.network([b.no('St4'), b.no('B0'), b.resetCoil('St4')], title: 'Koniec cyklu'),
    b.network([
      b.parallel([
        [b.no('St1')],
        [b.no('St2')],
      ]),
      b.coil('Y1'),
    ]),
    b.network([
      b.parallel([
        [b.no('St2')],
        [b.no('St3')],
      ]),
      b.coil('Y2'),
    ]),
    b.network([
      b.parallel([
        [b.no('St1')],
        [b.no('St2')],
        [b.no('St3')],
        [b.no('St4')],
      ]),
      b.coil('Busy'),
    ]),
    b.network([
      b.nc('ES'),
      b.parallel([
        [b.resetCoil('St1')],
        [b.resetCoil('St2')],
        [b.resetCoil('St3')],
        [b.resetCoil('St4')],
      ]),
    ], title: 'Wyłącznik bezpieczeństwa'),
  ]);
}

Simulation buildAndStart({int dwellMs = 0}) {
  final result = buildSimulation(SimulationProject(
    program: sequenceProgram(dwellMs: dwellMs),
    tags: tags,
    plant: twoCylinderPlant(),
  ));
  expect(result.plc.diagnostics, isEmpty, reason: result.plc.diagnostics.join('\n'));
  expect(result.plant.diagnostics, isEmpty, reason: result.plant.diagnostics.join('\n'));
  expect(result.ioDiagnostics, isEmpty, reason: result.ioDiagnostics.join('\n'));
  return result.simulation!..start();
}

/// Movement events (`1A+`, `2A-`, …) with their start time, until [ms] elapse.
///
/// A reed switch with ±3 mm range on a 100 mm stroke reports the end position
/// at 97 mm, so the next cylinder may start while the previous one covers the
/// last few millimetres — as on a real rig. Any earlier overlap is an error.
List<(String, int)> recordMotion(Simulation sim, int ms) {
  final events = <(String, int)>[];
  final last = {'1A': Motion.stopped, '2A': Motion.stopped};
  for (var t = 0; t < ms; t += sim.cycleMs) {
    sim.step();
    for (final id in last.keys) {
      final motion = sim.plant.cylinder(id)!.motion;
      if (motion != last[id] && motion != Motion.stopped) {
        events.add(('$id${motion == Motion.extending ? '+' : '-'}', sim.timeMs));
        final other = sim.plant.cylinder(id == '1A' ? '2A' : '1A')!;
        if (other.motion != Motion.stopped) {
          final remaining = other.motion == Motion.extending ? 1 - other.position : other.position;
          expect(remaining, lessThanOrEqualTo(0.03 + 1e-9), reason: '$id started too early (t=${sim.timeMs})');
        }
      }
      last[id] = motion;
    }
  }
  return events;
}

/// Presses the start button for one cycle — enough for the PLC to see it.
void pressStart(Simulation sim) {
  sim.plant.setControl('S1', 'press', true);
  sim.step();
  sim.plant.setControl('S1', 'press', false);
}

void main() {
  test('A+ B+ A- B- runs once per start press', () {
    final sim = buildAndStart();
    sim.run(100);
    expect(sim.plant.cylinder('1A')!.position, 0);

    pressStart(sim);
    final events = recordMotion(sim, 6000);
    expect(events.map((e) => e.$1), ['1A+', '2A+', '1A-', '2A-']);

    // Each stroke takes 1 s; the next one starts once the reed switch
    // reports the end position (97 mm of 100 mm), one cycle later.
    for (var i = 1; i < events.length; i++) {
      expect(events[i].$2 - events[i - 1].$2, inInclusiveRange(960, 990), reason: events.toString());
    }
    expect(sim.plant.cylinder('1A')!.position, 0);
    expect(sim.plant.cylinder('2A')!.position, 0);
    expect(sim.plant.indicator('H1')!.isOn, isFalse);
    expect(sim.plc.counter('Cycles')!.cv, 1);
  });

  test('lamp shows the running cycle', () {
    final sim = buildAndStart();
    pressStart(sim);
    sim.run(1500);
    expect(sim.plant.indicator('H1')!.isOn, isTrue);
  });

  test('dwell timer delays A- after B+', () {
    final sim = buildAndStart(dwellMs: 500);
    pressStart(sim);
    final events = recordMotion(sim, 7000);
    expect(events.map((e) => e.$1), ['1A+', '2A+', '1A-', '2A-']);
    final withoutDwell = buildAndStart();
    pressStart(withoutDwell);
    final reference = recordMotion(withoutDwell, 6000);
    final dwell = (events[2].$2 - events[1].$2) - (reference[2].$2 - reference[1].$2);
    expect(dwell, inInclusiveRange(500, 510));
  });

  test('emergency stop resets the sequence and blocks the start', () {
    final sim = buildAndStart();
    pressStart(sim);
    sim.run(1500); // 1A extended, 2A half way
    expect(sim.plant.cylinder('2A')!.motion, Motion.extending);

    sim.plant.setControl('ES', 'pressed', true);
    sim.run(1100);
    expect(sim.plant.cylinder('1A')!.position, 0, reason: 'monostable valves spring back');
    expect(sim.plant.cylinder('2A')!.position, 0);
    expect(sim.plant.indicator('H1')!.isOn, isFalse);

    pressStart(sim);
    sim.run(500);
    expect(sim.plant.cylinder('1A')!.position, 0, reason: 'start blocked while pressed');

    sim.plant.setControl('ES', 'pressed', false);
    pressStart(sim);
    sim.run(500);
    expect(sim.plant.cylinder('1A')!.position, greaterThan(0));
  });

  test('auto mode runs exactly three cycles counted by CTU', () {
    final sim = buildAndStart();
    sim.plant.setControl('S2', 'on', true);
    final events = recordMotion(sim, 16000);
    expect(events.map((e) => e.$1), [
      for (var i = 0; i < 3; i++) ...['1A+', '2A+', '1A-', '2A-'],
    ]);
    expect(sim.plc.counter('Cycles')!.cv, 3);
    expect(sim.plc.counter('Cycles')!.q, isTrue);
  });

  test('PLC STOP drops the outputs, the plant keeps running', () {
    final sim = buildAndStart();
    pressStart(sim);
    sim.run(500);
    sim.stop();
    sim.run(1000);
    expect(sim.plc.mode, PlcMode.stop);
    expect(sim.plant.cylinder('1A')!.position, 0);
  });

  test('forcing an output drives the plant directly', () {
    final sim = buildAndStart();
    sim.plc.force(BitAddress.parse('%Q0.1'), true);
    sim.run(1100);
    expect(sim.plant.cylinder('2A')!.position, 1);
    expect(sim.plc.readTag('B1'), isTrue, reason: 'reed switch reaches the PLC input');
  });
}
