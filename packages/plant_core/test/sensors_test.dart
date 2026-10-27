import 'package:plant_core/plant_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('sensors mounted on a cylinder', () {
    test('reed switch switches within its range around the mounting point', () {
      // Stroke 100 mm, range ±3 mm, mounted at 50 %.
      final sim = simulatorFor(cylinderCircuit()
        ..element('B3', 'reed_switch')
        ..mount('B3', '1A', 0.5));
      sim.setSignal('1V1', '14', true);
      final active = <int>[];
      for (var t = 10; t <= 1000; t += 10) {
        sim.step(10);
        if (sim.out('B3')) active.add(t);
      }
      expect(active, [470, 480, 490, 500, 510, 520, 530]);
    });

    test('reed switch needs a magnetic piston, inductive sensor does not', () {
      final plant = PlantBuilder()
        ..element('S', 'air_supply')
        ..element('V', 'valve_5_2')
        ..element('C', 'cylinder_double', params: {'magnetic_piston': false})
        ..element('Reed', 'reed_switch')
        ..element('Ind', 'inductive_sensor')
        ..element('Lim', 'limit_switch')
        ..connect('S.P', 'V.1')
        ..connect('V.4', 'C.A')
        ..connect('V.2', 'C.B')
        ..mount('Reed', 'C', 0)
        ..mount('Ind', 'C', 0)
        ..mount('Lim', 'C', 0);
      final result = buildPlant(plant.build());
      expect(result.warnings.map((d) => d.code), contains(PlantDiagnosticCode.reedWithoutMagnet));

      final sim = result.simulator!;
      sim.step(10);
      expect(sim.out('Reed'), isFalse);
      expect(sim.out('Ind'), isTrue);
      expect(sim.out('Lim'), isTrue);
    });

    test('NC contact inverts the output, active state stays physical', () {
      final sim = simulatorFor(cylinderCircuit()
        ..element('B3', 'inductive_sensor', params: {'contact': 'nc'})
        ..mount('B3', '1A', 0));
      sim.step(10);
      expect(sim.sensor('B3')!.active, isTrue);
      expect(sim.out('B3'), isFalse);
    });

    test('sensor outputs are valid right after building', () {
      final sim = simulatorFor(cylinderCircuit());
      expect(sim.out('1B1'), isTrue);
    });
  });

  test('pressure switch follows the line pressure', () {
    final sim = simulatorFor(cylinderCircuit()
      ..element('PS', 'pressure_switch', params: {'contact': 'no'})
      ..connect('PS.1', '1A.A'));
    expect(sim.out('PS'), isFalse);
    sim.setSignal('1V1', '14', true);
    sim.step(10);
    expect(sim.out('PS'), isTrue);
  });

  group('operator controls and indicators', () {
    late PlantSimulator sim;
    setUp(() {
      sim = simulatorFor(PlantBuilder()
        ..element('S1', 'push_button')
        ..element('S0', 'push_button', params: {'contact': 'nc', 'color': 'red'})
        ..element('S2', 'selector_switch')
        ..element('ES', 'emergency_stop')
        ..element('H1', 'lamp', params: {'color': 'red'})
        ..element('H2', 'buzzer'));
    });

    test('initial contact states', () {
      expect(sim.out('S1'), isFalse);
      expect(sim.out('S0'), isTrue, reason: 'NC button closed at rest');
      expect(sim.out('S2'), isFalse);
      expect(sim.out('ES'), isTrue, reason: 'emergency stop is NC');
    });

    test('pressing changes the contact at the next step', () {
      sim
        ..setControl('S1', 'press', true)
        ..setControl('S0', 'press', true)
        ..setControl('S2', 'on', true)
        ..setControl('ES', 'pressed', true);
      expect(sim.out('S1'), isFalse);
      sim.step(10);
      expect([sim.out('S1'), sim.out('S0'), sim.out('S2'), sim.out('ES')], [true, false, true, false]);
    });

    test('lamp and buzzer follow their PLC signal', () {
      expect(sim.indicator('H1')!.isOn, isFalse);
      sim.setSignal('H1', 'in', true);
      sim.setSignal('H2', 'in', true);
      expect(sim.indicator('H1')!.isOn, isTrue);
      expect(sim.indicator('H2')!.isOn, isTrue);
    });

    test('control definitions describe latching', () {
      final types = ElementCatalog.standard;
      final params = ParamValues(const {'contact': 'no', 'color': 'green'});
      expect(types['push_button']!.controls(params).single.latching, isFalse);
      expect(types['selector_switch']!.controls(params).single.latching, isTrue);
      expect(types['emergency_stop']!.controls(params).single.latching, isTrue);
    });
  });

  group('API misuse', () {
    test('signals produced by the plant cannot be driven', () {
      final sim = simulatorFor(cylinderCircuit());
      expect(() => sim.setSignal('1B1', 'out', true), throwsArgumentError);
      expect(() => sim.setSignal('1V1', '12', true), throwsArgumentError, reason: 'monostable has no 12');
      expect(() => sim.setSignal('nope', '14', true), throwsArgumentError);
      expect(() => sim.setControl('1V1', 'lever', true), throwsArgumentError);
      expect(() => sim.line(const PortRef('1A', 'X')), throwsArgumentError);
      expect(() => sim.step(0), throwsArgumentError);
    });
  });

  test('bindings list signals with PLC addresses', () {
    final sim = simulatorFor(PlantBuilder()
      ..element('S', 'air_supply')
      ..element('V', 'valve_5_2', params: {'actuation': Actuation.bistable}, io: {'14': '%Q0.0', '12': ' '})
      ..element('C', 'cylinder_double')
      ..element('B1', 'reed_switch', io: {'out': '%I0.0'})
      ..connect('S.P', 'V.1')
      ..connect('V.4', 'C.A')
      ..connect('V.2', 'C.B')
      ..mount('B1', 'C', 0));
    final bindings = {for (final b in sim.bindings) '${b.elementId}.${b.signal}': (b.direction, b.address)};
    expect(bindings, {
      'V.14': (SignalDirection.fromPlc, '%Q0.0'),
      'B1.out': (SignalDirection.toPlc, '%I0.0'),
    });
  });
}
